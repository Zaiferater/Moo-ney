using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Media;

namespace WorkdayTimer
{
    internal sealed class TypingCow : FrameworkElement, IWorkMascot
    {
        private static readonly Brush Halo = SetupWindow.Brush("#5069BEA6");
        private static readonly Brush Cream = SetupWindow.Brush("#FFF3DB");
        private static readonly Brush Cocoa = SetupWindow.Brush("#604843");
        private static readonly Brush Blush = SetupWindow.Brush("#F6B6AD");
        private static readonly Brush Gold = SetupWindow.Brush("#FFD98B");
        private static readonly Brush Laptop = SetupWindow.Brush("#38675D");
        private static readonly Brush Mint = SetupWindow.Brush("#A2E3CD");
        private static readonly Pen Outline = MakePen(Cocoa, 1.4);
        private static readonly Pen FaceLine = MakePen(Cocoa, 1.2);
        private static readonly Pen Spark = MakePen(Gold, 1.6);
        private readonly Stopwatch typing = new Stopwatch();
        private bool working;
        private int frame;

        public TypingCow()
        {
            System.Windows.Automation.AutomationProperties.SetName(this, "敲键盘的小牛");
        }

        public void ShowWork(bool isWorking, bool animate)
        {
            if (animate && !typing.IsRunning)
                typing.Restart();
            if (!animate)
                typing.Reset();

            int nextFrame = (int)(typing.ElapsedMilliseconds / 90 % 4);
            if (working == isWorking && frame == nextFrame)
                return;

            working = isWorking;
            frame = nextFrame;
            InvalidateVisual();
        }

        protected override void OnRender(DrawingContext drawing)
        {
            base.OnRender(drawing);
            double bob = working && frame % 2 == 1 ? 1.2 : 0;
            Ellipse(drawing, Halo, null, 33, 33, 32, 32);

            drawing.PushTransform(new TranslateTransform(0, bob));
            Ellipse(drawing, Gold, Outline, 23, 13, 4, 8);
            Ellipse(drawing, Gold, Outline, 43, 13, 4, 8);
            Ellipse(drawing, Cream, Outline, 15, 22, 8, 4.5);
            Ellipse(drawing, Cream, Outline, 51, 22, 8, 4.5);
            Ellipse(drawing, Blush, null, 14, 22, 4.5, 2);
            Ellipse(drawing, Blush, null, 52, 22, 4.5, 2);
            Ellipse(drawing, Cream, Outline, 33, 28, 18, 15.5);
            Ellipse(drawing, Cocoa, null, 41, 18, 5, 3);
            Ellipse(drawing, Cocoa, null, 24, 27, 1.5, 2);
            Ellipse(drawing, Cocoa, null, 42, 27, 1.5, 2);
            Ellipse(drawing, Blush, null, 20, 32, 2.5, 1.3);
            Ellipse(drawing, Blush, null, 46, 32, 2.5, 1.3);
            Ellipse(drawing, Blush, Outline, 33, 34.5, 9, 5.2);
            Ellipse(drawing, Cocoa, null, 30, 33.5, 1, 0.9);
            Ellipse(drawing, Cocoa, null, 36, 33.5, 1, 0.9);
            drawing.DrawGeometry(null, FaceLine, Geometry.Parse("M 30,36.5 Q 33,39 36,36.5"));
            drawing.Pop();

            double leftHoof = working && frame % 2 == 1 ? 48 : 51;
            double rightHoof = working && frame % 2 == 0 ? 48 : 51;
            Ellipse(drawing, Cream, Outline, 15, leftHoof, 5, 4);
            Ellipse(drawing, Cream, Outline, 51, rightHoof, 5, 4);
            drawing.DrawRoundedRectangle(Laptop, Outline, new Rect(17, 43, 32, 17), 3, 3);
            drawing.DrawRoundedRectangle(Mint, Outline, new Rect(13, 58, 40, 4), 2, 2);
            Ellipse(drawing, Gold, null, 33, 51, 2.3, 2.3);

            if (working)
            {
                int x = frame < 2 ? 55 : 10;
                drawing.DrawLine(Spark, new Point(x - 2, 39), new Point(x + 2, 39));
                drawing.DrawLine(Spark, new Point(x, 37), new Point(x, 41));
            }
        }

        private static void Ellipse(DrawingContext drawing, Brush fill, Pen pen, double x, double y, double rx, double ry)
        {
            drawing.DrawEllipse(fill, pen, new Point(x, y), rx, ry);
        }

        private static Pen MakePen(Brush brush, double width)
        {
            var pen = new Pen(brush, width) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
            pen.Freeze();
            return pen;
        }
    }
}
