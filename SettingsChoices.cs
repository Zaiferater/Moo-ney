using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Markup;

namespace WorkdayTimer
{
    internal sealed class TimeChoice : StackPanel
    {
        public readonly ComboBox Hour;
        private readonly ComboBox minute;

        public TimeChoice(string caption, int totalMinutes)
        {
            Orientation = Orientation.Horizontal;
            Hour = CreatePart(caption + "小时", 24, totalMinutes / 60);
            minute = CreatePart(caption + "分钟", 60, totalMinutes % 60);
            Children.Add(Hour);
            Children.Add(new TextBlock
            {
                Text = ":",
                Margin = new Thickness(8, 0, 8, 0),
                VerticalAlignment = VerticalAlignment.Center
            });
            Children.Add(minute);
        }

        public int TotalMinutes
        {
            get { return Hour.SelectedIndex * 60 + minute.SelectedIndex; }
        }

        private static ComboBox CreatePart(string name, int count, int selected)
        {
            var part = new ComboBox
            {
                Width = 76,
                MinHeight = 32,
                MaxDropDownHeight = 240,
                Padding = new Thickness(0),
                HorizontalContentAlignment = HorizontalAlignment.Center,
                VerticalContentAlignment = VerticalAlignment.Center
            };
            AutomationProperties.SetName(part, name);
            for (int value = 0; value < count; value++)
                part.Items.Add(value.ToString("D2", CultureInfo.InvariantCulture));
            part.SelectedIndex = selected;
            return part;
        }
    }

    internal static class AppearanceControlStyles
    {
        public static void Install(Window window)
        {
            window.Resources[typeof(ComboBox)] = (Style)XamlReader.Parse(@"
<Style xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation"" TargetType=""ComboBox"">
  <Setter Property=""Foreground"" Value=""{DynamicResource Appearance.Text}""/>
  <Setter Property=""Background"" Value=""{DynamicResource Appearance.Field}""/>
  <Setter Property=""BorderBrush"" Value=""{DynamicResource Appearance.Border}""/>
  <Setter Property=""Template"">
    <Setter.Value>
      <ControlTemplate TargetType=""ComboBox"">
        <Grid>
          <ToggleButton Name=""DropDownButton"" Focusable=""False"" ClickMode=""Press""
            Foreground=""{TemplateBinding Foreground}"" Background=""{TemplateBinding Background}""
            BorderBrush=""{TemplateBinding BorderBrush}""
            IsChecked=""{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}"">
            <ToggleButton.Template>
              <ControlTemplate TargetType=""ToggleButton"">
                <Border Name=""Field"" Background=""{TemplateBinding Background}"" BorderBrush=""{TemplateBinding BorderBrush}""
                  BorderThickness=""1"" CornerRadius=""4"">
                  <Path Data=""M 0,0 L 3.5,3.5 L 7,0"" Stroke=""{TemplateBinding Foreground}"" StrokeThickness=""1.25""
                    StrokeStartLineCap=""Round"" StrokeEndLineCap=""Round""
                    HorizontalAlignment=""Right"" VerticalAlignment=""Center"" Margin=""0,0,9,0""/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property=""IsMouseOver"" Value=""True"">
                    <Setter TargetName=""Field"" Property=""BorderBrush"" Value=""{DynamicResource Appearance.Accent}""/>
                  </Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate>
            </ToggleButton.Template>
          </ToggleButton>
          <ContentPresenter Content=""{TemplateBinding SelectionBoxItem}"" ContentTemplate=""{TemplateBinding SelectionBoxItemTemplate}""
            IsHitTestVisible=""False"" Margin=""6,0,23,0"" VerticalAlignment=""Center""
            HorizontalAlignment=""{TemplateBinding HorizontalContentAlignment}""/>
          <Popup Name=""PART_Popup"" Placement=""Bottom"" IsOpen=""{TemplateBinding IsDropDownOpen}""
            AllowsTransparency=""True"" Focusable=""False"">
            <Border Background=""{TemplateBinding Background}"" BorderBrush=""{TemplateBinding BorderBrush}"" BorderThickness=""1""
              CornerRadius=""4"" Padding=""2"" MinWidth=""{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}""
              MaxHeight=""{TemplateBinding MaxDropDownHeight}"">
              <ScrollViewer VerticalScrollBarVisibility=""Auto"" HorizontalScrollBarVisibility=""Disabled"">
                <ItemsPresenter KeyboardNavigation.DirectionalNavigation=""Contained""/>
              </ScrollViewer>
            </Border>
          </Popup>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property=""IsKeyboardFocusWithin"" Value=""True"">
            <Setter TargetName=""DropDownButton"" Property=""BorderBrush"" Value=""{DynamicResource Appearance.Accent}""/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>");
            window.Resources[typeof(ComboBoxItem)] = (Style)XamlReader.Parse(@"
<Style xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation"" TargetType=""ComboBoxItem"">
  <Setter Property=""Foreground"" Value=""{DynamicResource Appearance.Text}""/>
  <Setter Property=""Padding"" Value=""5,3""/>
  <Setter Property=""MinHeight"" Value=""28""/>
  <Setter Property=""Template"">
    <Setter.Value>
      <ControlTemplate TargetType=""ComboBoxItem"">
        <Border Name=""Row"" Background=""Transparent"" Padding=""{TemplateBinding Padding}"" CornerRadius=""3"">
          <ContentPresenter VerticalAlignment=""Center""/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property=""IsHighlighted"" Value=""True"">
            <Setter TargetName=""Row"" Property=""Background"" Value=""{DynamicResource Appearance.Highlight}""/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>");
        }
    }
}
