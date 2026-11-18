using System;
using System.Globalization;
using System.Security.Principal;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace WorkdayTimer
{
    internal static class Program
    {
        public const string Title = "牛马打气机";
        private static readonly Lazy<ImageSource> icon = new Lazy<ImageSource>(LoadIcon);

        public static ImageSource Icon
        {
            get { return icon.Value; }
        }

        private static ImageSource LoadIcon()
        {
            using (var stream = typeof(Program).Assembly.GetManifestResourceStream("WorkdayTimer.App.ico"))
            {
                var image = BitmapFrame.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                image.Freeze();
                return image;
            }
        }

        [STAThread]
        private static void Main()
        {
            using (var user = WindowsIdentity.GetCurrent())
                Run(new SettingsStore(), @"Local\WorkdayTimer." + user.User.Value);
        }

        internal static void Run(SettingsStore store, string instanceName)
        {
            using (var activate = new EventWaitHandle(false, EventResetMode.AutoReset, instanceName + ".Activate"))
            using (var instance = new Mutex(false, instanceName))
            {
                bool ownsInstance;
                try { ownsInstance = instance.WaitOne(0); }
                catch (AbandonedMutexException) { ownsInstance = true; }
                if (!ownsInstance)
                {
                    activate.Set();
                    return;
                }

                try
                {
                    var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
                    var controller = new TimerApplication(app, store);
                    var activation = ThreadPool.RegisterWaitForSingleObject(activate,
                        delegate { app.Dispatcher.BeginInvoke(new Action(controller.ShowRunningWindow)); },
                        null, Timeout.Infinite, false);
                    try
                    {
                        app.Startup += delegate { controller.Start(); };
                        app.Run();
                    }
                    finally
                    {
                        activation.Unregister(null);
                    }
                }
                finally
                {
                    instance.ReleaseMutex();
                }
            }
        }
    }

    internal sealed class TimerApplication
    {
        private readonly Application app;
        private readonly SettingsStore store;
        private Settings settings;
        private SetupWindow setup;
        private TimerWindow timer;
        private string loadError;

        public TimerApplication(Application app, SettingsStore store)
        {
            this.app = app;
            this.store = store;
            try
            {
                bool recovered;
                settings = store.Load(out recovered);
                if (recovered)
                    loadError = "已从备份恢复上一次可用的设置。";
            }
            catch (Exception error)
            {
                if (!SettingsStore.IsSettingsError(error))
                    throw;
                loadError = "读取设置失败，请重新填写后打开计时器。";
            }
        }

        public void Start()
        {
            if (settings == null)
                ShowSettings();
            else
                ShowTimer();
        }

        public void ShowRunningWindow()
        {
            Window window = (Window)setup ?? timer;
            if (window != null)
                Present(window);
        }

        public void ShowSettings()
        {
            if (setup == null)
            {
                setup = new SetupWindow(settings, loadError, OpenTimer, PreviewAppearance);
                if (timer != null)
                    setup.Owner = timer;
                setup.Closed += delegate
                {
                    setup = null;
                    if (timer == null)
                        app.Shutdown();
                    else if (!app.Dispatcher.HasShutdownStarted)
                        timer.SetAppearance(settings.MascotId, settings.ThemeId);
                };
                setup.Show();
            }
            Present(setup);
        }

        private void PreviewAppearance(string mascotId, string themeId)
        {
            if (timer != null)
                timer.SetAppearance(mascotId, themeId);
        }

        private static void Present(Window window)
        {
            if (window.WindowState == WindowState.Minimized)
                window.WindowState = WindowState.Normal;
            if (!window.Activate() && !window.Topmost)
            {
                window.Topmost = true;
                window.Topmost = false;
            }
        }

        private void OpenTimer(Settings next)
        {
            if (settings != null)
                next.AlwaysOnTop = settings.AlwaysOnTop;
            SetCurrentPosition(next);
            try
            {
                store.Save(next);
            }
            catch (Exception error)
            {
                if (!SettingsStore.IsSettingsError(error))
                    throw;
                setup.ShowSaveError();
                return;
            }
            settings = next;
            loadError = null;

            if (timer == null)
                ShowTimer();
            else
                timer.UpdateSettings(settings);
            setup.Close();
        }

        private void ShowTimer()
        {
            timer = new TimerWindow(settings, ShowSettings, SavePosition, ChangeTopmost, app.Shutdown);
            timer.Closed += delegate
            {
                timer = null;
                if (setup == null)
                    app.Shutdown();
            };
            timer.Show();
            Present(timer);
        }

        private void SetCurrentPosition(Settings next)
        {
            if (timer != null)
            {
                Point position = timer.ExpandedPosition;
                next.Left = position.X;
                next.Top = position.Y;
            }
            else if (settings != null)
            {
                next.Left = settings.Left;
                next.Top = settings.Top;
            }
        }

        private void SavePosition(double left, double top)
        {
            var next = settings.Copy();
            next.Left = left;
            next.Top = top;
            if (TrySave(next, "无法保存悬浮窗位置。"))
            {
                settings.Left = left;
                settings.Top = top;
            }
        }

        private void ChangeTopmost(bool enabled)
        {
            var next = settings.Copy();
            next.AlwaysOnTop = enabled;
            SetCurrentPosition(next);
            if (TrySave(next, "无法保存置顶选项，请检查设置文件是否可写。"))
            {
                settings = next;
                timer.UpdateSettings(next);
            }
        }

        private bool TrySave(Settings next, string errorMessage)
        {
            try
            {
                store.Save(next);
                return true;
            }
            catch (Exception error)
            {
                if (!SettingsStore.IsSettingsError(error))
                    throw;
                MessageBox.Show(timer, errorMessage, Program.Title, MessageBoxButton.OK, MessageBoxImage.Warning);
                return false;
            }
        }
    }

    internal sealed class SetupWindow : Window
    {
        private readonly TextBox payInput;
        private readonly TimeChoice startChoice;
        private readonly TimeChoice endChoice;
        private readonly TextBlock feedback;
        private readonly ComboBox mascotChoice;
        private readonly ComboBox themeChoice;
        private readonly MascotView mascotPreview;
        private readonly Border previewFrame;
        private readonly Button open;
        private readonly RadioButton customWorkdays;
        private DateTime[] workdayOverrides;

        public SetupWindow(Settings settings, string loadError, Action<Settings> openTimer,
            Action<string, string> previewAppearance = null)
        {
            Title = Program.Title;
            Icon = Program.Icon;
            Width = 386;
            MaxHeight = SystemParameters.WorkArea.Height;
            SizeToContent = SizeToContent.Height;
            ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            FontFamily = new FontFamily("Microsoft YaHei UI");
            FontSize = 13;
            UseLayoutRounding = true;
            AppearanceControlStyles.Install(this);

            var content = new StackPanel { Margin = new Thickness(25, 22, 25, 24) };
            Content = new ScrollViewer
            {
                Content = content,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
            };
            content.Children.Add(new TextBlock
            {
                Text = Program.Title,
                FontSize = 24,
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(0, 0, 0, 12)
            });

            bool useCustomWorkdays = settings != null && settings.UseCustomWorkdays;
            workdayOverrides = settings == null ? new DateTime[0] : settings.WorkdayOverrides;
            var workdayMode = new WrapPanel();
            var weekdays = CreateWorkdayMode("周一至周五", !useCustomWorkdays);
            customWorkdays = CreateWorkdayMode("自定义工作日", useCustomWorkdays);
            var editCalendar = new Button
            {
                Content = "编辑日历…",
                MinHeight = 29,
                Padding = new Thickness(7, 2, 7, 2),
                Visibility = useCustomWorkdays ? Visibility.Visible : Visibility.Collapsed
            };
            editCalendar.SetResourceReference(Control.ForegroundProperty, "Appearance.Text");
            editCalendar.SetResourceReference(Control.BackgroundProperty, "Appearance.Field");
            editCalendar.SetResourceReference(Control.BorderBrushProperty, "Appearance.Border");
            customWorkdays.Checked += delegate { editCalendar.Visibility = Visibility.Visible; };
            customWorkdays.Unchecked += delegate { editCalendar.Visibility = Visibility.Collapsed; };
            editCalendar.Click += delegate
            {
                var calendar = new WorkdayCalendarWindow(workdayOverrides,
                    AppTheme.Resolve(GetChoiceId(themeChoice)), DateTime.Today) { Owner = this };
                if (calendar.ShowDialog() == true)
                    workdayOverrides = calendar.WorkdayOverrides;
            };
            workdayMode.Children.Add(weekdays);
            workdayMode.Children.Add(customWorkdays);
            workdayMode.Children.Add(editCalendar);
            AddField(content, "计薪日期", workdayMode, useCustomWorkdays ? customWorkdays : weekdays);

            payInput = new TextBox
            {
                Text = settings == null ? "" : settings.MonthlyPay.ToString("0.##", CultureInfo.InvariantCulture),
                MinHeight = 32,
                Padding = new Thickness(8, 0, 8, 0),
                VerticalContentAlignment = VerticalAlignment.Center
            };
            AddField(content, "月薪（元）", payInput, payInput);

            startChoice = new TimeChoice("上班", settings == null ? 9 * 60 : settings.StartMinutes);
            endChoice = new TimeChoice("下班", settings == null ? 18 * 60 : settings.EndMinutes);
            AddField(content, "上班时间", startChoice, startChoice.Hour);
            AddField(content, "下班时间", endChoice, endChoice.Hour);

            string mascotId = MascotChoice.Resolve(settings == null ? null : settings.MascotId).Id;
            string themeId = AppTheme.Resolve(settings == null ? null : settings.ThemeId).Id;
            mascotChoice = CreatePicker();
            foreach (var choice in MascotChoice.Choices)
                mascotChoice.Items.Add(CreateOption(choice.Id, choice.Name, new MascotView(choice.Id, 26)));
            mascotChoice.SelectedValue = mascotId;

            themeChoice = CreatePicker();
            foreach (var choice in AppTheme.Choices)
            {
                var swatch = new Border
                {
                    Width = 21,
                    Height = 21,
                    CornerRadius = new CornerRadius(5),
                    Background = choice.TimerBackground,
                    BorderBrush = choice.FieldBorder,
                    BorderThickness = new Thickness(1)
                };
                themeChoice.Items.Add(CreateOption(choice.Id, choice.Name, swatch));
            }
            themeChoice.SelectedValue = themeId;

            var appearance = new Grid();
            appearance.ColumnDefinitions.Add(new ColumnDefinition());
            appearance.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var pickers = new StackPanel();
            AddField(pickers, "形象", mascotChoice, mascotChoice);
            AddField(pickers, "主题色", themeChoice, themeChoice);
            appearance.Children.Add(pickers);
            mascotPreview = new MascotView(mascotId, 66);
            previewFrame = new Border
            {
                Width = 83,
                Height = 83,
                CornerRadius = new CornerRadius(42),
                BorderThickness = new Thickness(1),
                Margin = new Thickness(15, 0, 0, 10),
                VerticalAlignment = VerticalAlignment.Center,
                Child = mascotPreview
            };
            Grid.SetColumn(previewFrame, 1);
            appearance.Children.Add(previewFrame);
            content.Children.Add(appearance);

            feedback = new TextBlock
            {
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 0, 0, 10),
                Text = loadError ?? "",
                Visibility = loadError == null ? Visibility.Collapsed : Visibility.Visible
            };
            content.Children.Add(feedback);

            open = new Button
            {
                Content = settings == null ? "打开计时器" : "保存设置",
                IsDefault = true,
                MinHeight = 38,
                FontWeight = FontWeights.SemiBold,
                Cursor = Cursors.Hand
            };
            open.Click += delegate { Apply(openTimer); };
            content.Children.Add(open);

            ApplyAppearance(mascotId, themeId);
            SelectionChangedEventHandler appearanceChanged = delegate
            {
                string selectedMascot = GetChoiceId(mascotChoice);
                string selectedTheme = GetChoiceId(themeChoice);
                ApplyAppearance(selectedMascot, selectedTheme);
                if (previewAppearance != null)
                    previewAppearance(selectedMascot, selectedTheme);
            };
            mascotChoice.SelectionChanged += appearanceChanged;
            themeChoice.SelectionChanged += appearanceChanged;

            var animatePreview = new DispatcherTimer(DispatcherPriority.Background)
            {
                Interval = TimeSpan.FromMilliseconds(60)
            };
            animatePreview.Tick += delegate { mascotPreview.ShowWork(true, SystemParameters.ClientAreaAnimation); };
            Loaded += delegate { payInput.Focus(); payInput.SelectAll(); animatePreview.Start(); };
            Closed += delegate { animatePreview.Stop(); };
        }

        private static ComboBox CreatePicker()
        {
            return new ComboBox
            {
                MinHeight = 35,
                MaxDropDownHeight = 250,
                SelectedValuePath = "Tag",
                HorizontalContentAlignment = HorizontalAlignment.Left
            };
        }

        private static RadioButton CreateWorkdayMode(string label, bool selected)
        {
            var option = new RadioButton
            {
                GroupName = "WorkdayMode",
                Content = label,
                IsChecked = selected,
                Margin = new Thickness(0, 0, 12, 0),
                VerticalAlignment = VerticalAlignment.Center,
                VerticalContentAlignment = VerticalAlignment.Center
            };
            option.SetResourceReference(Control.ForegroundProperty, "Appearance.Text");
            return option;
        }

        private static string GetChoiceId(ComboBox picker)
        {
            var choice = picker.SelectedItem as ComboBoxItem;
            return choice == null ? null : (string)choice.Tag;
        }

        private static ComboBoxItem CreateOption(string id, string name, FrameworkElement image)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(new Border { Width = 28, Child = image });
            var caption = new TextBlock
            {
                Text = name,
                Margin = new Thickness(6, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            caption.SetResourceReference(TextBlock.ForegroundProperty, "Appearance.Text");
            row.Children.Add(caption);
            var item = new ComboBoxItem { Content = row, Tag = id };
            TextSearch.SetText(item, name);
            return item;
        }

        private void ApplyAppearance(string mascotId, string themeId)
        {
            AppTheme theme = AppTheme.Resolve(themeId);
            Background = theme.SettingsBackground;
            Foreground = theme.Text;
            Resources["Appearance.Text"] = theme.Text;
            Resources["Appearance.Field"] = theme.FieldBackground;
            Resources["Appearance.Border"] = theme.FieldBorder;
            Resources["Appearance.Accent"] = theme.Action;
            Resources["Appearance.Highlight"] = theme.PinBackground;
            payInput.Foreground = theme.Text;
            payInput.Background = theme.FieldBackground;
            payInput.BorderBrush = theme.FieldBorder;
            open.Background = theme.Action;
            open.BorderBrush = theme.Action;
            open.Foreground = theme.ActionText;
            feedback.Foreground = theme.Error;
            previewFrame.Background = theme.FieldBackground;
            previewFrame.BorderBrush = theme.FieldBorder;
            mascotPreview.Select(mascotId);
            mascotPreview.ShowWork(true, SystemParameters.ClientAreaAnimation);
        }

        private static void AddField(Panel panel, string caption, FrameworkElement field, UIElement focusTarget)
        {
            var label = new Label
            {
                Content = caption,
                Target = focusTarget,
                Padding = new Thickness(0, 0, 0, 4)
            };
            label.SetResourceReference(Control.ForegroundProperty, "Appearance.Text");
            panel.Children.Add(label);
            field.Margin = new Thickness(0, 0, 0, 12);
            panel.Children.Add(field);
        }

        private void Apply(Action<Settings> openTimer)
        {
            decimal pay;
            if (!decimal.TryParse(payInput.Text.Trim(), NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out pay)
                || pay < 0 || pay > 99999999.99m || decimal.Round(pay, 2) != pay)
            {
                ShowError("请输入 0 至 99999999.99 元的月薪，最多两位小数。", payInput);
                payInput.SelectAll();
                return;
            }
            int start = startChoice.TotalMinutes;
            int end = endChoice.TotalMinutes;
            if (end <= start)
            {
                ShowError("下班时间须晚于当天的上班时间。", endChoice.Hour);
                return;
            }
            openTimer(new Settings
            {
                MonthlyPay = pay,
                StartMinutes = start,
                EndMinutes = end,
                MascotId = MascotChoice.Resolve(GetChoiceId(mascotChoice)).Id,
                ThemeId = AppTheme.Resolve(GetChoiceId(themeChoice)).Id,
                UseCustomWorkdays = customWorkdays.IsChecked == true,
                WorkdayOverrides = workdayOverrides
            });
        }

        internal void ShowSaveError()
        {
            ShowError("保存设置失败，请确认当前用户有权限写入本地应用数据。", null);
        }

        private void ShowError(string text, Control field)
        {
            feedback.Text = text;
            feedback.Visibility = Visibility.Visible;
            if (field != null)
                field.Focus();
        }

        internal static SolidColorBrush Brush(string hex)
        {
            var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
            brush.Freeze();
            return brush;
        }
    }
}
