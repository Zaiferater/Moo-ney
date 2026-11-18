using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace WorkdayTimer
{
    internal sealed class AppTheme
    {
        public const string DefaultId = "lilac";
        public static readonly AppTheme[] Choices =
        {
            new AppTheme(DefaultId, "薰衣草紫", "#B1EADAFB", "#312343", "#563277", "#404177",
                "#F7F0FC", "#FFFAFF", "#CFBBE1", "#64428B", "#FFFFFF", "#C4AFDF", "#983C45"),
            new AppTheme("mint", "薄荷青", "#B9D8EEE6", "#193B34", "#245B4C", "#205D60",
                "#EDF8F4", "#F7FFFB", "#A5C8BB", "#28695D", "#FFFFFF", "#ABD3C5", "#963C35"),
            new AppTheme("peach", "杏桃橙", "#BCFCE4CE", "#492D23", "#833D21", "#775025",
                "#FFF4E8", "#FFFBF5", "#E5BFA2", "#914B2B", "#FFFFFF", "#EAB797", "#9C372E"),
            new AppTheme("glacier", "冰川蓝", "#BADEEEFF", "#17364E", "#16487B", "#205763",
                "#EDF6FF", "#F8FCFF", "#AAC6DF", "#286188", "#FFFFFF", "#A7C9E9", "#8D3540"),
            new AppTheme("smoke", "烟灰蓝", "#C8324258", "#F8FAFF", "#FFE9AD", "#D5F4FF",
                "#3E5066", "#4B5D74", "#8298B0", "#C8DEFA", "#1C2F44", "#536B86", "#FFD1CC")
        };

        public readonly string Id;
        public readonly string Name;
        public readonly Brush TimerBackground;
        public readonly Brush Text;
        public readonly Brush TodayAmount;
        public readonly Brush MonthAmount;
        public readonly Brush SettingsBackground;
        public readonly Brush FieldBackground;
        public readonly Brush FieldBorder;
        public readonly Brush Action;
        public readonly Brush ActionText;
        public readonly Brush PinBackground;
        public readonly Brush Error;

        private AppTheme(string id, string name, string timerBackground, string text, string todayAmount,
            string monthAmount, string settingsBackground, string fieldBackground, string fieldBorder,
            string action, string actionText, string pinBackground, string error)
        {
            Id = id;
            Name = name;
            TimerBackground = SetupWindow.Brush(timerBackground);
            Text = SetupWindow.Brush(text);
            TodayAmount = SetupWindow.Brush(todayAmount);
            MonthAmount = SetupWindow.Brush(monthAmount);
            SettingsBackground = SetupWindow.Brush(settingsBackground);
            FieldBackground = SetupWindow.Brush(fieldBackground);
            FieldBorder = SetupWindow.Brush(fieldBorder);
            Action = SetupWindow.Brush(action);
            ActionText = SetupWindow.Brush(actionText);
            PinBackground = SetupWindow.Brush(pinBackground);
            Error = SetupWindow.Brush(error);
        }

        public static AppTheme Resolve(string id)
        {
            foreach (var theme in Choices)
                if (theme.Id == id)
                    return theme;
            return Choices[0];
        }
    }

    internal sealed class MascotChoice
    {
        public const string DefaultId = "cow";
        public static readonly MascotChoice[] Choices =
        {
            new MascotChoice(DefaultId, "打字小牛"),
            new MascotChoice("panda", "开会小熊猫"),
            new MascotChoice("cat", "赶日报的橘猫"),
            new MascotChoice("penguin", "改稿企鹅")
        };

        public readonly string Id;
        public readonly string Name;

        private MascotChoice(string id, string name)
        {
            Id = id;
            Name = name;
        }

        public static MascotChoice Resolve(string id)
        {
            foreach (var choice in Choices)
                if (choice.Id == id)
                    return choice;
            return Choices[0];
        }
    }

    internal interface IWorkMascot
    {
        void ShowWork(bool working, bool animate);
    }

    internal sealed class MascotView : Decorator
    {
        private IWorkMascot mascot;
        public string MascotId { get; private set; }

        public MascotView(string id, double size)
        {
            Width = size;
            Height = size;
            RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
            Select(id);
        }

        public void Select(string id)
        {
            MascotChoice choice = MascotChoice.Resolve(id);
            if (MascotId == choice.Id)
                return;

            MascotId = choice.Id;
            FrameworkElement art = choice.Id == MascotChoice.DefaultId
                ? (FrameworkElement)new TypingCow() : new SpriteMascot(choice.Id);
            art.Width = art.Height = 66;
            mascot = (IWorkMascot)art;
            Child = new Viewbox { Child = art };
            System.Windows.Automation.AutomationProperties.SetName(this, choice.Name);
        }

        public void ShowWork(bool working, bool animate)
        {
            mascot.ShowWork(working, animate);
        }
    }

    internal sealed class SpriteMascot : FrameworkElement, IWorkMascot
    {
        // The first 12 cells show each working pose. The next 12 repeat the poses with a blink.
        private const int PoseCount = 12;
        private static readonly Dictionary<string, BitmapSource[]> cache = new Dictionary<string, BitmapSource[]>();
        private readonly BitmapSource[] images;
        private readonly Stopwatch clock = new Stopwatch();
        private int frame;

        public SpriteMascot(string id)
        {
            if (!cache.TryGetValue(id, out images))
            {
                images = ReadFrames(id);
                cache.Add(id, images);
            }
        }

        private static BitmapSource[] ReadFrames(string id)
        {
            using (var stream = typeof(SpriteMascot).Assembly.GetManifestResourceStream("WorkdayTimer.Mascots." + id + ".png"))
            {
                var strip = BitmapFrame.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                int size = strip.PixelHeight;
                var frames = new BitmapSource[2 * PoseCount];
                for (int index = 0; index < frames.Length; index++)
                {
                    var image = new CroppedBitmap(strip, new Int32Rect(index * size, 0, size, size));
                    image.Freeze();
                    frames[index] = image;
                }
                return frames;
            }
        }

        public void ShowWork(bool working, bool animate)
        {
            if (working && animate)
                clock.Start();
            else
                clock.Reset();

            long tick = clock.ElapsedMilliseconds / 142;
            int next = (int)(tick % PoseCount) + (tick % 25 == 22 ? PoseCount : 0);
            if (next == frame)
                return;
            frame = next;
            InvalidateVisual();
        }

        protected override void OnRender(DrawingContext drawing)
        {
            base.OnRender(drawing);
            drawing.DrawImage(images[frame], new Rect(RenderSize));
        }
    }
}
