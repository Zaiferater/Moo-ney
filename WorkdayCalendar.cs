using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;

namespace WorkdayTimer
{
    internal sealed class WorkdayCalendarWindow : Window
    {
        private static readonly string[] weekdayNames = { "一", "二", "三", "四", "五", "六", "日" };
        private readonly HashSet<DateTime> overrides;
        private readonly AppTheme theme;
        private readonly ControlTemplate buttonTemplate;
        private readonly UniformGrid days;
        private readonly TextBlock monthLabel;
        private readonly TextBlock selectedCount;
        private readonly Button previous;
        private readonly Button next;
        private DateTime month;

        public WorkdayCalendarWindow(DateTime[] workdayOverrides, AppTheme theme, DateTime today)
        {
            overrides = new HashSet<DateTime>(workdayOverrides);
            this.theme = theme;
            month = new DateTime(today.Year, today.Month, 1);
            Title = "自定义工作日";
            Icon = Program.Icon;
            Width = 384;
            SizeToContent = SizeToContent.Height;
            ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;
            ShowInTaskbar = false;
            FontFamily = new FontFamily("Microsoft YaHei UI");
            FontSize = 13;
            UseLayoutRounding = true;
            Background = theme.SettingsBackground;
            Foreground = theme.Text;
            Resources["Appearance.Accent"] = theme.Action;
            buttonTemplate = CreateButtonTemplate();

            var content = new StackPanel { Margin = new Thickness(20) };
            Content = content;
            content.Children.Add(new TextBlock
            {
                Text = "点击日期切换，选中的日期计薪。",
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 0, 0, 12)
            });

            var navigation = new DockPanel { Margin = new Thickness(2, 0, 2, 9) };
            previous = CreateMonthButton("‹", "上一月", -1);
            next = CreateMonthButton("›", "下一月", 1);
            DockPanel.SetDock(next, Dock.Right);
            navigation.Children.Add(previous);
            navigation.Children.Add(next);
            monthLabel = new TextBlock
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                FontSize = 17,
                FontWeight = FontWeights.SemiBold
            };
            navigation.Children.Add(monthLabel);
            content.Children.Add(navigation);

            var weekdays = new UniformGrid { Columns = 7, Rows = 1, Margin = new Thickness(0, 0, 0, 5) };
            foreach (string name in weekdayNames)
                weekdays.Children.Add(new TextBlock { Text = name, HorizontalAlignment = HorizontalAlignment.Center });
            content.Children.Add(weekdays);
            days = new UniformGrid { Columns = 7, Rows = 6 };
            content.Children.Add(days);

            var footer = new DockPanel { Margin = new Thickness(0, 14, 0, 0) };
            var actions = new StackPanel { Orientation = Orientation.Horizontal };
            DockPanel.SetDock(actions, Dock.Right);
            var cancel = CreateButton("取消");
            cancel.IsCancel = true;
            var confirm = CreateButton("确定");
            confirm.IsDefault = true;
            confirm.Margin = new Thickness(7, 0, 0, 0);
            confirm.Background = theme.Action;
            confirm.Foreground = theme.ActionText;
            confirm.BorderBrush = theme.Action;
            confirm.Click += delegate { DialogResult = true; };
            actions.Children.Add(cancel);
            actions.Children.Add(confirm);
            footer.Children.Add(actions);
            selectedCount = new TextBlock { VerticalAlignment = VerticalAlignment.Center };
            footer.Children.Add(selectedCount);
            content.Children.Add(footer);

            ShowMonth();
        }

        public DateTime[] WorkdayOverrides
        {
            get
            {
                var dates = new DateTime[overrides.Count];
                overrides.CopyTo(dates);
                return dates;
            }
        }

        private void ShowMonth()
        {
            monthLabel.Text = month.ToString("yyyy年 M月", CultureInfo.InvariantCulture);
            previous.IsEnabled = month.Year > 1 || month.Month > 1;
            next.IsEnabled = month.Year < 9999 || month.Month < 12;
            days.Children.Clear();
            int firstColumn = ((int)month.DayOfWeek + 6) % 7;
            for (int index = 0; index < firstColumn; index++)
                days.Children.Add(new Border());
            int length = DateTime.DaysInMonth(month.Year, month.Month);
            for (int index = 0; index < length; index++)
                days.Children.Add(CreateDay(month.AddDays(index)));
            UpdateCount();
        }

        private ToggleButton CreateDay(DateTime date)
        {
            var day = new ToggleButton
            {
                Content = date.Day.ToString(CultureInfo.InvariantCulture),
                Tag = date,
                Template = buttonTemplate,
                IsChecked = IsWorkday(date),
                MinHeight = 33,
                Margin = new Thickness(2),
                Padding = new Thickness(0),
                BorderThickness = new Thickness(1),
                Cursor = Cursors.Hand
            };
            AutomationProperties.SetName(day, date.ToString("yyyy年M月d日", CultureInfo.GetCultureInfo("zh-CN")));
            ApplyDayColor(day);
            day.Checked += OnDayChanged;
            day.Unchecked += OnDayChanged;
            return day;
        }

        private void OnDayChanged(object sender, RoutedEventArgs args)
        {
            var day = (ToggleButton)sender;
            var date = (DateTime)day.Tag;
            if ((day.IsChecked == true) == Settings.IsWeekday(date))
                overrides.Remove(date);
            else
                overrides.Add(date);
            ApplyDayColor(day);
            UpdateCount();
        }

        private void ApplyDayColor(ToggleButton day)
        {
            bool selected = day.IsChecked == true;
            day.Background = selected ? theme.Action : theme.FieldBackground;
            day.Foreground = selected ? theme.ActionText : theme.Text;
            day.BorderBrush = selected ? theme.Action : theme.FieldBorder;
        }

        private bool IsWorkday(DateTime date)
        {
            return Settings.IsWeekday(date) != overrides.Contains(date);
        }

        private void UpdateCount()
        {
            int count = 0;
            foreach (UIElement cell in days.Children)
            {
                var day = cell as ToggleButton;
                if (day != null && day.IsChecked == true)
                    count++;
            }
            selectedCount.Text = string.Format(CultureInfo.InvariantCulture, "本月计薪 {0} 天", count);
        }

        private Button CreateMonthButton(string arrow, string name, int offset)
        {
            var button = CreateButton(arrow);
            button.MinWidth = button.MinHeight = 32;
            button.FontSize = 19;
            button.Padding = new Thickness(0);
            button.ToolTip = name;
            AutomationProperties.SetName(button, name);
            button.Click += delegate { month = month.AddMonths(offset); ShowMonth(); };
            return button;
        }

        private Button CreateButton(string label)
        {
            return new Button
            {
                Content = label,
                Template = buttonTemplate,
                Background = theme.FieldBackground,
                Foreground = theme.Text,
                BorderBrush = theme.FieldBorder,
                BorderThickness = new Thickness(1),
                Padding = new Thickness(10, 4, 10, 4),
                MinHeight = 32,
                Cursor = Cursors.Hand
            };
        }

        private static ControlTemplate CreateButtonTemplate()
        {
            return (ControlTemplate)XamlReader.Parse(@"
<ControlTemplate xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation"" TargetType=""ButtonBase"">
  <Border Name=""Surface"" Background=""{TemplateBinding Background}"" BorderBrush=""{TemplateBinding BorderBrush}""
    BorderThickness=""{TemplateBinding BorderThickness}"" Padding=""{TemplateBinding Padding}"" CornerRadius=""5"">
    <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center"" />
  </Border>
  <ControlTemplate.Triggers>
    <Trigger Property=""IsMouseOver"" Value=""True"">
      <Setter TargetName=""Surface"" Property=""Opacity"" Value=""0.84"" />
    </Trigger>
    <Trigger Property=""IsKeyboardFocused"" Value=""True"">
      <Setter TargetName=""Surface"" Property=""BorderBrush"" Value=""{DynamicResource Appearance.Accent}"" />
      <Setter TargetName=""Surface"" Property=""BorderThickness"" Value=""2"" />
    </Trigger>
    <Trigger Property=""IsEnabled"" Value=""False"">
      <Setter TargetName=""Surface"" Property=""Opacity"" Value=""0.42"" />
    </Trigger>
  </ControlTemplate.Triggers>
</ControlTemplate>");
        }
    }
}
