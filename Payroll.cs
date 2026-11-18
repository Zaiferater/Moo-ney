using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Xml.Serialization;

namespace WorkdayTimer
{
    public sealed class Settings
    {
        public decimal MonthlyPay { get; set; }
        public int StartMinutes { get; set; }
        public int EndMinutes { get; set; }
        public double? Left { get; set; }
        public double? Top { get; set; }
        public bool AlwaysOnTop { get; set; }
        public string MascotId { get; set; }
        public string ThemeId { get; set; }
        public bool UseCustomWorkdays { get; set; }
        private DateTime[] workdayOverrides = new DateTime[0];

        [XmlArrayItem("Date", DataType = "date")]
        public DateTime[] WorkdayOverrides
        {
            get { return (DateTime[])workdayOverrides.Clone(); }
            set
            {
                var dates = new SortedSet<DateTime>();
                if (value != null)
                    foreach (DateTime day in value)
                        dates.Add(day.Date);
                workdayOverrides = new DateTime[dates.Count];
                dates.CopyTo(workdayOverrides);
            }
        }

        public Settings()
        {
            MonthlyPay = -1;
            StartMinutes = -1;
            AlwaysOnTop = true;
            MascotId = MascotChoice.DefaultId;
            ThemeId = AppTheme.DefaultId;
        }

        internal Settings Copy()
        {
            return (Settings)MemberwiseClone();
        }

        internal static bool IsWeekday(DateTime day)
        {
            return day.DayOfWeek != DayOfWeek.Saturday && day.DayOfWeek != DayOfWeek.Sunday;
        }

        internal bool IsWorkday(DateTime day)
        {
            bool weekday = IsWeekday(day);
            return UseCustomWorkdays && Array.BinarySearch(workdayOverrides, day.Date) >= 0 ? !weekday : weekday;
        }

        public bool IsValid()
        {
            return MonthlyPay >= 0 && MonthlyPay <= 99999999.99m
                && decimal.Round(MonthlyPay, 2) == MonthlyPay && StartMinutes >= 0
                && EndMinutes < 24 * 60 && EndMinutes > StartMinutes;
        }
    }

    internal sealed class SettingsStore
    {
        private readonly string filePath;
        private readonly string backupPath;
        private readonly XmlSerializer serializer = new XmlSerializer(typeof(Settings));

        public SettingsStore() : this(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WorkdayTimer", "settings.xml"))
        {
        }

        internal SettingsStore(string filePath)
        {
            this.filePath = filePath;
            backupPath = filePath + ".bak";
        }

        public Settings Load(out bool recovered)
        {
            recovered = false;
            Exception primaryError;
            Exception backupError;
            var primary = Read(filePath, out primaryError);
            var backup = Read(backupPath, out backupError);
            if (primary != null)
            {
                if (backup == null)
                    TryRepair(delegate { CreateBackup(filePath); });
                return primary;
            }

            if (backup == null)
            {
                if (primaryError != null || backupError != null)
                    throw new InvalidDataException("No readable settings file.", primaryError ?? backupError);
                return null;
            }

            recovered = true;
            TryRepair(delegate { Save(backup); });
            return backup;
        }

        private static void TryRepair(Action repair)
        {
            try { repair(); }
            catch (Exception error)
            {
                if (!IsSettingsError(error))
                    throw;
            }
        }

        private Settings Read(string path, out Exception failure)
        {
            failure = null;
            try
            {
                using (var stream = File.OpenRead(path))
                {
                    var settings = (Settings)serializer.Deserialize(stream);
                    if (settings == null || !settings.IsValid())
                        throw new InvalidDataException("Invalid settings values.");
                    return settings;
                }
            }
            catch (FileNotFoundException) { return null; }
            catch (DirectoryNotFoundException) { return null; }
            catch (Exception error)
            {
                if (!IsSettingsError(error))
                    throw;
                failure = error;
                return null;
            }
        }

        public void Save(Settings settings)
        {
            if (!settings.IsValid())
                throw new InvalidDataException("Invalid settings values.");
            Directory.CreateDirectory(Path.GetDirectoryName(filePath));
            string temporaryPath = filePath + "." + Guid.NewGuid().ToString("N");
            try
            {
                using (var stream = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write))
                {
                    serializer.Serialize(stream, settings);
                    stream.Flush(true);
                }

                Exception ignored;
                bool copyPrevious = Read(filePath, out ignored) != null;
                if (!copyPrevious && Read(backupPath, out ignored) == null)
                    CreateBackup(temporaryPath);
                Publish(temporaryPath, filePath, copyPrevious ? backupPath : null);
            }
            finally
            {
                File.Delete(temporaryPath);
            }
        }

        private void CreateBackup(string sourcePath)
        {
            string temporaryPath = backupPath + "." + Guid.NewGuid().ToString("N");
            try
            {
                File.Copy(sourcePath, temporaryPath);
                Publish(temporaryPath, backupPath, null);
            }
            finally
            {
                File.Delete(temporaryPath);
            }
        }

        private static void Publish(string temporaryPath, string filePath, string backupPath)
        {
            if (File.Exists(filePath))
                File.Replace(temporaryPath, filePath, backupPath);
            else
                File.Move(temporaryPath, filePath);
        }

        internal static bool IsSettingsError(Exception error)
        {
            return error is IOException || error is InvalidDataException
                || error is UnauthorizedAccessException || error is InvalidOperationException;
        }
    }

    internal enum WorkStatus { BeforeWork, Working, AfterWork, DayOff }

    internal sealed class PaySnapshot
    {
        public decimal TodayPay { get; private set; }
        public decimal MonthPay { get; private set; }
        public TimeSpan Worked { get; private set; }
        public TimeSpan Remaining { get; private set; }
        public WorkStatus Status { get; private set; }
        public TimeSpan UntilBreak { get; private set; }
        public bool IsOnBreak { get; private set; }

        public static PaySnapshot At(Settings settings, DateTime now)
        {
            DateTime monthStart = new DateTime(now.Year, now.Month, 1);
            int daysInMonth = DateTime.DaysInMonth(now.Year, now.Month);
            int workdays = 0;
            int completedDays = 0;
            for (int index = 0; index < daysInMonth; index++)
            {
                if (!settings.IsWorkday(monthStart.AddDays(index)))
                    continue;

                workdays++;
                if (index < now.Day - 1)
                    completedDays++;
            }

            var start = TimeSpan.FromMinutes(settings.StartMinutes);
            var end = TimeSpan.FromMinutes(settings.EndMinutes);
            var duration = end - start;
            var snapshot = new PaySnapshot();
            if (!settings.IsWorkday(now))
                snapshot.Status = WorkStatus.DayOff;
            else if (now.TimeOfDay < start)
                snapshot.Status = WorkStatus.BeforeWork;
            else if (now.TimeOfDay >= end)
            {
                snapshot.Status = WorkStatus.AfterWork;
                snapshot.Worked = duration;
            }
            else
            {
                snapshot.Status = WorkStatus.Working;
                snapshot.Worked = now.TimeOfDay - start;
                snapshot.Remaining = end - now.TimeOfDay;
            }

            snapshot.IsOnBreak = snapshot.Status == WorkStatus.DayOff;
            if (!snapshot.IsOnBreak)
            {
                DateTime lastWorkday = now.Date;
                while (lastWorkday < DateTime.MaxValue.Date && settings.IsWorkday(lastWorkday.AddDays(1)))
                    lastWorkday = lastWorkday.AddDays(1);

                TimeSpan untilBreak = lastWorkday.Add(end) - now;
                snapshot.IsOnBreak = untilBreak <= TimeSpan.Zero;
                if (!snapshot.IsOnBreak)
                    snapshot.UntilBreak = untilBreak;
            }

            if (workdays == 0)
                return snapshot;

            decimal workedTicks = snapshot.Worked.Ticks;
            decimal monthTicks = (decimal)duration.Ticks * workdays;
            snapshot.TodayPay = settings.MonthlyPay * workedTicks / monthTicks;
            snapshot.MonthPay = settings.MonthlyPay
                * (completedDays * (decimal)duration.Ticks + workedTicks) / monthTicks;
            return snapshot;
        }

        public static string Clock(long seconds)
        {
            return TimeSpan.FromSeconds(seconds).ToString(@"hh\:mm\:ss", CultureInfo.InvariantCulture);
        }

        public static string BreakClock(TimeSpan remaining)
        {
            var rounded = TimeSpan.FromMinutes(Math.Ceiling(remaining.TotalMinutes));
            return string.Format(CultureInfo.InvariantCulture, "{0}天{1}小时{2}分钟",
                rounded.Days, rounded.Hours, rounded.Minutes);
        }
    }
}
