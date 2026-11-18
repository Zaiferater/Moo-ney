using System;
using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace WorkdayTimer
{
    internal sealed class TimerWindow : Window
    {
        private const double ExpandedWidth = 510;
        private const double ExpandedHeight = 118;
        private const double CompactSize = 70;
        private static readonly Point ExpandedCowOrigin = new Point(12, 24);
        private static readonly Brush ToolBackground = SetupWindow.Brush("#48FFFFFF");
        private static readonly DependencyProperty CollapseProgressProperty = DependencyProperty.Register(
            "CollapseProgress", typeof(double), typeof(TimerWindow), new PropertyMetadata(0d,
                (owner, change) => ((TimerWindow)owner).DrawPresentation((double)change.NewValue)));

        private readonly RollingAmount today;
        private readonly RollingAmount month;
        private readonly TextBlock remaining;
        private readonly TextBlock breakCountdown;
        private readonly MascotView mascot;
        private readonly DispatcherTimer refresh;
        private readonly Border card;
        private readonly ScaleTransform cardScale = new ScaleTransform();
        private readonly Ellipse circle;
        private readonly Button cowButton;
        private readonly ToggleButton pinButton;
        private readonly MenuItem pinItem;
        private readonly Action<double, double> savePosition;
        private Point compactOffset = ExpandedCowOrigin;
        private Point? cowPress;
        private bool compactRequested;
        private bool compactLayout;
        private AppTheme theme;
        private Settings settings;

        public TimerWindow(Settings settings, Action showSettings, Action<double, double> savePosition,
            Action<bool> changeTopmost, Action exit)
        {
            this.settings = settings;
            this.savePosition = savePosition;
            Title = Program.Title;
            Icon = Program.Icon;
            Width = ExpandedWidth;
            Height = ExpandedHeight;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowActivated = false;
            ShowInTaskbar = false;
            FontFamily = new FontFamily("Microsoft YaHei UI");
            UseLayoutRounding = true;
            Place(settings);

            var row = new Grid();
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(78) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.RowDefinitions.Add(new RowDefinition { Height = new GridLength(31) });
            row.RowDefinitions.Add(new RowDefinition());
            card = new Border
            {
                Width = ExpandedWidth,
                Height = ExpandedHeight,
                BorderBrush = SetupWindow.Brush("#9BFFFFFF"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(24),
                Padding = new Thickness(13, 9, 13, 10),
                Child = row,
                RenderTransform = cardScale
            };
            var surface = new Canvas { ClipToBounds = true };
            surface.Children.Add(card);
            Content = surface;

            mascot = new MascotView(settings.MascotId, 66) { IsHitTestVisible = false };
            circle = new Ellipse
            {
                StrokeThickness = 1,
                IsHitTestVisible = false
            };
            var cowFace = new Grid();
            cowFace.Children.Add(circle);
            cowFace.Children.Add(mascot);
            cowButton = new Button
            {
                Width = CompactSize,
                Height = CompactSize,
                Cursor = Cursors.Hand,
                Content = cowFace,
                Template = (ControlTemplate)XamlReader.Parse(@"
<ControlTemplate xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation"" TargetType=""Button"">
    <Grid>
        <Ellipse Fill=""Transparent"" />
        <ContentPresenter />
    </Grid>
</ControlTemplate>")
            };
            cowButton.Click += delegate { ToggleCompact(); };
            cowButton.PreviewMouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs args)
            {
                cowPress = args.GetPosition(this);
            };
            cowButton.LostMouseCapture += delegate { cowPress = null; };
            cowButton.PreviewMouseMove += OnCowMouseMove;
            surface.Children.Add(cowButton);
            UpdateCowAction();
            DrawPresentation(0);

            var heading = new TextBlock
            {
                Text = Program.Title,
                FontSize = 20,
                FontWeight = FontWeights.SemiBold,
                RenderTransform = new TranslateTransform(0, 3),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(heading, 1);
            Grid.SetColumnSpan(heading, 2);
            row.Children.Add(heading);

            var tools = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Top
            };
            var toolTemplate = CreateToolTemplate();
            pinButton = new ToggleButton();
            ConfigureTool(pinButton, toolTemplate, "始终置顶",
                "M 7,2 H 17 V 5 L 15,7 V 11 L 18,15 V 16 H 6 V 15 L 9,11 V 7 L 7,5 Z M 12,16 V 22");
            var editButton = new Button();
            ConfigureTool(editButton, toolTemplate, "设置",
                "M 9,2 H 15 L 16,5 H 19 L 22,10 L 20,12 L 22,14 L 19,19 H 16 L 15,22 H 9 L 8,19 H 5 L 2,14 L 4,12 L 2,10 L 5,5 H 8 Z M 15,12 A 3,3 0 1 1 9,12 A 3,3 0 1 1 15,12 Z");
            editButton.Click += delegate { showSettings(); };
            var close = new Button();
            ConfigureTool(close, toolTemplate, "退出程序", "M 0,0 L 8,8 M 8,0 L 0,8", 9);
            close.Click += delegate { exit(); };
            tools.Children.Add(pinButton);
            tools.Children.Add(editButton);
            tools.Children.Add(close);
            Grid.SetColumn(tools, 2);
            row.Children.Add(tools);

            today = new RollingAmount(23);
            month = new RollingAmount(22);
            remaining = AddColumn(row, 1, "今日已赚", today);
            breakCountdown = AddColumn(row, 2, "本月已赚", month);

            var menu = new ContextMenu();
            var edit = new MenuItem { Header = "设置" };
            edit.Click += delegate { showSettings(); };
            pinItem = new MenuItem { Header = "始终置顶", IsCheckable = true };
            RoutedEventHandler togglePin = delegate(object sender, RoutedEventArgs args)
            {
                bool enabled = sender == pinButton ? pinButton.IsChecked == true : pinItem.IsChecked;
                if (enabled == this.settings.AlwaysOnTop)
                    return;
                changeTopmost(enabled);
                ApplyTopmost();
            };
            pinButton.Checked += togglePin;
            pinButton.Unchecked += togglePin;
            pinItem.Checked += togglePin;
            pinItem.Unchecked += togglePin;
            var quit = new MenuItem { Header = "退出计时器" };
            quit.Click += delegate { exit(); };
            menu.Items.Add(edit);
            menu.Items.Add(pinItem);
            menu.Items.Add(quit);
            card.ContextMenu = menu;
            cowButton.ContextMenu = menu;
            SetAppearance(settings.MascotId, settings.ThemeId);

            card.MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs args)
            {
                if (args.ClickCount == 2)
                {
                    showSettings();
                    return;
                }
                DragAndSave();
            };

            refresh = new DispatcherTimer(DispatcherPriority.Background)
            {
                Interval = TimeSpan.FromMilliseconds(50)
            };
            refresh.Tick += delegate { Refresh(DateTime.Now); };
            Loaded += delegate { Refresh(DateTime.Now); refresh.Start(); };
            Closed += delegate { refresh.Stop(); };
            Refresh(DateTime.Now);
        }

        public void UpdateSettings(Settings next)
        {
            bool appearanceChanged = settings.MascotId != next.MascotId || settings.ThemeId != next.ThemeId;
            settings = next;
            if (appearanceChanged)
                SetAppearance(next.MascotId, next.ThemeId);
            ApplyTopmost();
            Refresh(DateTime.Now, false);
        }

        public void SetAppearance(string mascotId, string themeId)
        {
            mascot.Select(mascotId);
            AppTheme palette = AppTheme.Resolve(themeId);
            if (palette == theme)
                return;

            theme = palette;
            Foreground = theme.Text;
            Resources["Appearance.Text"] = theme.Text;
            Resources["Appearance.Accent"] = theme.Action;
            card.Background = theme.TimerBackground;
            circle.Fill = theme.SettingsBackground;
            circle.Stroke = theme.FieldBorder;
            today.SetForeground(theme.TodayAmount);
            month.SetForeground(theme.MonthAmount);
            ApplyTopmost();
        }

        private void ApplyTopmost()
        {
            bool enabled = settings.AlwaysOnTop;
            Topmost = enabled;
            pinButton.IsChecked = enabled;
            pinButton.Background = enabled ? theme.PinBackground : ToolBackground;
            pinItem.IsChecked = enabled;
            pinButton.ToolTip = enabled ? "始终置顶已开启，单击关闭" : "始终置顶已关闭，单击开启";
        }

        public Point ExpandedPosition
        {
            get
            {
                return compactLayout
                    ? FitExpanded(new Point(Left - ExpandedCowOrigin.X, Top - ExpandedCowOrigin.Y))
                    : new Point(Left, Top);
            }
        }

        private void ToggleCompact()
        {
            double from = (double)GetValue(CollapseProgressProperty);
            compactRequested = !compactRequested;
            UpdateCowAction();
            if (!compactRequested && compactLayout)
            {
                Point origin = ExpandedPosition;
                compactOffset = new Point(Left - origin.X, Top - origin.Y);
                compactLayout = false;
                SetBounds(origin, ExpandedWidth, ExpandedHeight);
                DrawPresentation(from);
                UpdateLayout();
                Refresh(DateTime.Now, false);
            }

            card.Visibility = Visibility.Visible;
            card.IsHitTestVisible = false;
            double target = compactRequested ? 1 : 0;
            if (!SystemParameters.ClientAreaAnimation || from == target)
            {
                FinishTransition(target);
                return;
            }

            var transition = new DoubleAnimation(from, target, TimeSpan.FromMilliseconds(180))
            {
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
            };
            transition.Completed += delegate
            {
                if (compactRequested == (target == 1))
                    FinishTransition(target);
            };
            BeginAnimation(CollapseProgressProperty, transition, HandoffBehavior.SnapshotAndReplace);
        }

        private void FinishTransition(double target)
        {
            SetValue(CollapseProgressProperty, target);
            BeginAnimation(CollapseProgressProperty, null);
            if (target == 1)
            {
                card.Visibility = Visibility.Collapsed;
                compactLayout = true;
                SetBounds(new Point(Left + compactOffset.X, Top + compactOffset.Y), CompactSize, CompactSize);
            }
            else
            {
                card.IsHitTestVisible = true;
            }
            compactOffset = ExpandedCowOrigin;
            DrawPresentation(target);
            UpdateLayout();
        }

        private void DrawPresentation(double progress)
        {
            double cowX = ExpandedCowOrigin.X + (compactOffset.X - ExpandedCowOrigin.X) * progress;
            double cowY = ExpandedCowOrigin.Y + (compactOffset.Y - ExpandedCowOrigin.Y) * progress;
            Canvas.SetLeft(cowButton, compactLayout ? 0 : cowX);
            Canvas.SetTop(cowButton, compactLayout ? 0 : cowY);
            card.RenderTransformOrigin = new Point(
                (cowX + CompactSize / 2) / ExpandedWidth, (cowY + CompactSize / 2) / ExpandedHeight);
            cardScale.ScaleX = 1 - progress * (1 - CompactSize / ExpandedWidth);
            cardScale.ScaleY = 1 - progress * (1 - CompactSize / ExpandedHeight);
            card.Opacity = 1 - progress;
            circle.Opacity = progress;
        }

        private void UpdateCowAction()
        {
            string action = compactRequested ? "展开悬浮窗" : "收起悬浮窗";
            cowButton.ToolTip = action + " · 拖动移动 · 右键菜单";
            System.Windows.Automation.AutomationProperties.SetName(cowButton, action);
        }

        private void OnCowMouseMove(object sender, MouseEventArgs args)
        {
            if (!cowPress.HasValue || !cowButton.IsMouseCaptured || args.LeftButton != MouseButtonState.Pressed
                || (!compactLayout && !card.IsHitTestVisible))
                return;
            Vector travel = args.GetPosition(this) - cowPress.Value;
            if (Math.Abs(travel.X) < SystemParameters.MinimumHorizontalDragDistance
                && Math.Abs(travel.Y) < SystemParameters.MinimumVerticalDragDistance)
                return;

            cowButton.ReleaseMouseCapture();
            args.Handled = true;
            DragAndSave();
        }

        private void DragAndSave()
        {
            Point previous = new Point(Left, Top);
            DragMove();
            if (previous.X == Left && previous.Y == Top)
                return;
            Point position = ExpandedPosition;
            savePosition(position.X, position.Y);
        }

        private void SetBounds(Point origin, double width, double height)
        {
            Left = origin.X;
            Top = origin.Y;
            Width = width;
            Height = height;
        }

        private Point FitExpanded(Point desired)
        {
            var area = System.Windows.Forms.Screen.FromHandle(new WindowInteropHelper(this).Handle).WorkingArea;
            Point minimum = PointFromScreen(new Point(area.Left, area.Top)) + new Vector(Left, Top);
            Point maximum = PointFromScreen(new Point(area.Right, area.Bottom)) + new Vector(Left, Top);
            return new Point(Math.Max(minimum.X, Math.Min(desired.X, maximum.X - ExpandedWidth)),
                Math.Max(minimum.Y, Math.Min(desired.Y, maximum.Y - ExpandedHeight)));
        }

        private static void ConfigureTool(ButtonBase button, ControlTemplate template, string name, string geometry,
            double iconSize = 14)
        {
            button.Width = 26;
            button.Height = 26;
            button.Margin = new Thickness(4, 0, 0, 0);
            button.Cursor = Cursors.Hand;
            button.ToolTip = name;
            button.Template = template;
            button.Background = ToolBackground;
            var icon = new Path
            {
                Data = Geometry.Parse(geometry),
                StrokeThickness = 1.3,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round,
                StrokeLineJoin = PenLineJoin.Round,
                Width = iconSize,
                Height = iconSize,
                Stretch = Stretch.Uniform
            };
            icon.SetResourceReference(Shape.StrokeProperty, "Appearance.Text");
            button.Content = icon;
            System.Windows.Automation.AutomationProperties.SetName(button, name);
        }

        private static ControlTemplate CreateToolTemplate()
        {
            return (ControlTemplate)XamlReader.Parse(@"
<ControlTemplate xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation"" TargetType=""ButtonBase"">
    <Border Name=""Surface"" Background=""{TemplateBinding Background}"" CornerRadius=""8"" BorderThickness=""1"">
        <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center""/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property=""IsMouseOver"" Value=""True"">
            <Setter TargetName=""Surface"" Property=""Background"" Value=""#80FFFFFF""/>
        </Trigger>
        <Trigger Property=""IsPressed"" Value=""True"">
            <Setter TargetName=""Surface"" Property=""Background"" Value=""#50A887C7""/>
        </Trigger>
        <Trigger Property=""IsKeyboardFocused"" Value=""True"">
            <Setter TargetName=""Surface"" Property=""BorderBrush"" Value=""{DynamicResource Appearance.Accent}""/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>");
        }

        private void Place(Settings settings)
        {
            Rect workArea = SystemParameters.WorkArea;
            Rect desktop = new Rect(SystemParameters.VirtualScreenLeft, SystemParameters.VirtualScreenTop,
                SystemParameters.VirtualScreenWidth, SystemParameters.VirtualScreenHeight);
            if (settings.Left.HasValue && settings.Top.HasValue
                && desktop.Contains(new Point(settings.Left.Value, settings.Top.Value)))
            {
                Left = Math.Min(settings.Left.Value, desktop.Right - Width);
                Top = Math.Min(settings.Top.Value, desktop.Bottom - Height);
            }
            else
            {
                Left = workArea.Right - Width - 18;
                Top = workArea.Bottom - Height - 18;
            }
        }

        private static TextBlock AddColumn(Grid row, int column, string caption, RollingAmount amount)
        {
            var panel = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(panel, column);
            Grid.SetRow(panel, 1);
            row.Children.Add(panel);
            var payRow = new Grid();
            payRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            payRow.ColumnDefinitions.Add(new ColumnDefinition());
            panel.Children.Add(payRow);
            payRow.Children.Add(new TextBlock
            {
                Text = caption,
                FontSize = 13,
                Margin = new Thickness(0, 0, 7, 0),
                VerticalAlignment = VerticalAlignment.Center
            });
            Grid.SetColumn(amount, 1);
            payRow.Children.Add(amount);
            var clock = new TextBlock
            {
                FontSize = 13,
                Margin = new Thickness(0, 5, 0, 0)
            };
            panel.Children.Add(clock);
            return clock;
        }

        private void Refresh(DateTime now, bool allowMotion = true)
        {
            var snapshot = PaySnapshot.At(settings, now);
            bool working = snapshot.Status == WorkStatus.Working;
            bool animate = allowMotion && working && SystemParameters.ClientAreaAnimation;
            mascot.ShowWork(working, animate);
            if (compactLayout)
                return;
            today.SetAmount(snapshot.TodayPay, animate && !compactRequested);
            month.SetAmount(snapshot.MonthPay, animate && !compactRequested);
            SetText(breakCountdown, snapshot.IsOnBreak
                ? "放假中" : "距离放假还有 " + PaySnapshot.BreakClock(snapshot.UntilBreak));
            switch (snapshot.Status)
            {
                case WorkStatus.Working:
                    SetText(remaining, "距离下班还有  " + PaySnapshot.Clock((long)Math.Ceiling(snapshot.Remaining.TotalSeconds)));
                    break;
                case WorkStatus.BeforeWork:
                    SetText(remaining, "未上班");
                    break;
                case WorkStatus.AfterWork:
                    SetText(remaining, "已下班");
                    break;
                case WorkStatus.DayOff:
                    SetText(remaining, "今日休息");
                    break;
            }
        }

        private static void SetText(TextBlock block, string text)
        {
            if (block.Text != text)
                block.Text = text;
        }
    }

    internal sealed class RollingAmount : FrameworkElement
    {
        private readonly Typeface typeface = new Typeface("Consolas");
        private Brush foreground;
        private readonly double textSize;
        private readonly Stopwatch transition = new Stopwatch();
        private FormattedText[] glyphs;
        private double pixelsPerDip;
        private string previous = "";
        private string current = "";
        private decimal currentAmount;
        private bool animating;

        public RollingAmount(double textSize)
        {
            this.textSize = textSize;
            Height = Math.Ceiling(textSize * 1.25);
            ClipToBounds = true;
            Unloaded += delegate { StopAnimation(); };
        }

        public void SetForeground(Brush brush)
        {
            if (foreground == brush)
                return;
            foreground = brush;
            glyphs = null;
            InvalidateVisual();
        }

        public void SetAmount(decimal amount, bool animate)
        {
            string next = "¥" + amount.ToString("F5", CultureInfo.InvariantCulture);
            if (next == current)
            {
                if (!animate && animating)
                {
                    StopAnimation();
                    InvalidateVisual();
                }
                return;
            }
            bool moves = animate && current.Length > 0 && amount > currentAmount;
            previous = current;
            current = next;
            currentAmount = amount;
            System.Windows.Automation.AutomationProperties.SetName(this, next);
            if (moves)
            {
                transition.Restart();
                if (!animating)
                {
                    CompositionTarget.Rendering += OnFrame;
                    animating = true;
                }
            }
            else
            {
                StopAnimation();
            }
            InvalidateVisual();
        }

        private void OnFrame(object sender, EventArgs args)
        {
            if (transition.Elapsed.TotalMilliseconds >= 44)
                StopAnimation();
            InvalidateVisual();
        }

        private void StopAnimation()
        {
            if (!animating)
                return;
            CompositionTarget.Rendering -= OnFrame;
            animating = false;
        }

        protected override void OnRender(DrawingContext drawing)
        {
            base.OnRender(drawing);
            if (current.Length == 0)
                return;

            double dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
            if (glyphs == null || dpi != pixelsPerDip)
            {
                pixelsPerDip = dpi;
                glyphs = new FormattedText[12];
                const string characters = "0123456789¥.";
                for (int index = 0; index < characters.Length; index++)
                    glyphs[index] = new FormattedText(characters[index].ToString(), CultureInfo.InvariantCulture,
                        FlowDirection.LeftToRight, typeface, textSize, foreground, dpi);
            }

            double cell = glyphs[0].Width;
            double scale = Math.Min(1, ActualWidth / (cell * current.Length));
            if (scale <= 0)
                return;
            drawing.PushTransform(new ScaleTransform(scale, 1));
            double line = glyphs[0].Height;
            double baseline = (ActualHeight - line) / 2;
            double progress = Math.Min(1, transition.Elapsed.TotalMilliseconds / 44);
            for (int index = 0; index < current.Length; index++)
            {
                char digit = current[index];
                double x = index * cell;
                int previousIndex = index + previous.Length - current.Length;
                char old = previousIndex >= 0 && previousIndex < previous.Length ? previous[previousIndex] : ' ';
                if (animating && IsDigit(digit) && IsDigit(old) && digit != old)
                {
                    drawing.DrawText(Glyph(old), new Point(x, baseline - progress * line));
                    drawing.DrawText(Glyph(digit), new Point(x, baseline + (1 - progress) * line));
                }
                else
                {
                    drawing.DrawText(Glyph(digit), new Point(x, baseline));
                }
            }
            drawing.Pop();
        }

        private static bool IsDigit(char value)
        {
            return value >= '0' && value <= '9';
        }

        private FormattedText Glyph(char value)
        {
            return glyphs[value == '¥' ? 10 : value == '.' ? 11 : value - '0'];
        }
    }
}
