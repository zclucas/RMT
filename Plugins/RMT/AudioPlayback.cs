using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;

namespace RMT
{
    public sealed class AudioPlayback
    {
        private static readonly Lazy<Dispatcher> AudioDispatcher = new Lazy<Dispatcher>(StartDispatcher);
        // Keep detached playbacks alive until their media and event handlers can be released.
        private static readonly HashSet<AudioPlayback> Active = new HashSet<AudioPlayback>();
        private MediaPlayer player;
        private DispatcherTimer openTimer;
        private string midiAlias;
        private DispatcherTimer midiTimer;
        private volatile string state = "Idle";
        private string errorMessage = "";

        public string State { get { return state; } }
        public string ErrorMessage { get { return errorMessage; } }

        public void Start(string path)
        {
            if (state != "Idle")
                throw new InvalidOperationException("Create a separate playback for each audio file.");

            string fullPath = Path.GetFullPath(path);
            if (!File.Exists(fullPath))
                throw new FileNotFoundException("Audio file not found.", fullPath);

            state = "Opening";
            AudioDispatcher.Value.BeginInvoke(new Action(() => Open(fullPath)));
        }

        public void Cancel()
        {
            AudioDispatcher.Value.BeginInvoke(new Action(() =>
            {
                if (state == "Opening" || state == "Playing")
                    Finish("Cancelled");
            }));
        }

        private static Dispatcher StartDispatcher()
        {
            var ready = new TaskCompletionSource<Dispatcher>();
            var thread = new Thread(() =>
            {
                ready.SetResult(Dispatcher.CurrentDispatcher);
                Dispatcher.Run();
            });
            thread.Name = "RMT audio";
            thread.IsBackground = true;
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            return ready.Task.Result;
        }

        private void Open(string path)
        {
            Active.Add(this);
            try
            {
                string extension = Path.GetExtension(path).ToLowerInvariant();
                if (extension == ".mid" || extension == ".midi")
                {
                    OpenMidi(path);
                    return;
                }

                player = new MediaPlayer { Volume = 1.0 };
                player.MediaOpened += OnOpened;
                player.MediaEnded += OnEnded;
                player.MediaFailed += OnFailed;
                openTimer = new DispatcherTimer();
                openTimer.Interval = TimeSpan.FromSeconds(15);
                openTimer.Tick += OnOpenTimeout;
                openTimer.Start();
                player.Open(new Uri(path, UriKind.Absolute));
            }
            catch (Exception ex)
            {
                Finish("Failed", ex.Message);
            }
        }

        // WPF does not reliably open MIDI files. Keep playback windowless with the Windows sequencer.
        private void OpenMidi(string path)
        {
            string alias = "rmtMidi" + Guid.NewGuid().ToString("N");
            MidiCommand("open \"" + path + "\" type sequencer alias " + alias);
            midiAlias = alias;
            MidiCommand("play " + alias);
            midiTimer = new DispatcherTimer();
            midiTimer.Interval = TimeSpan.FromMilliseconds(50);
            midiTimer.Tick += OnMidiTick;
            midiTimer.Start();
            state = "Playing";
        }

        private void OnMidiTick(object sender, EventArgs e)
        {
            try
            {
                if (MidiCommand("status " + midiAlias + " mode") == "stopped")
                    Finish("Finished");
            }
            catch (Exception ex)
            {
                Finish("Failed", ex.Message);
            }
        }

        [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
        private static extern uint mciSendString(string command, StringBuilder result, int length, IntPtr callback);

        [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
        private static extern bool mciGetErrorString(uint error, StringBuilder message, int length);

        private static string MidiCommand(string command)
        {
            var result = new StringBuilder(256);
            uint error = mciSendString(command, result, result.Capacity, IntPtr.Zero);
            if (error != 0)
            {
                if (!mciGetErrorString(error, result, result.Capacity))
                    throw new InvalidOperationException("MIDI error " + error);
                throw new InvalidOperationException(result.ToString());
            }
            return result.ToString();
        }

        private void OnOpened(object sender, EventArgs e)
        {
            StopOpenTimer();
            try
            {
                if (!player.HasAudio)
                {
                    Finish("Failed", "The file contains no playable audio.");
                    return;
                }
                player.Play();
                state = "Playing";
            }
            catch (Exception ex)
            {
                Finish("Failed", ex.Message);
            }
        }

        private void OnOpenTimeout(object sender, EventArgs e)
        {
            Finish("Failed", "Opening the audio file timed out.");
        }

        private void OnEnded(object sender, EventArgs e)
        {
            Finish("Finished");
        }

        private void OnFailed(object sender, ExceptionEventArgs e)
        {
            Finish("Failed", e.ErrorException != null ? e.ErrorException.Message : "Media playback failed.");
        }

        private void StopOpenTimer()
        {
            if (openTimer == null)
                return;
            openTimer.Stop();
            openTimer.Tick -= OnOpenTimeout;
            openTimer = null;
        }

        private void Finish(string finalState, string error = "")
        {
            StopOpenTimer();
            try
            {
                if (midiTimer != null)
                {
                    midiTimer.Stop();
                    midiTimer.Tick -= OnMidiTick;
                    midiTimer = null;
                }
                if (midiAlias != null)
                {
                    MidiCommand("close " + midiAlias);
                    midiAlias = null;
                }
                if (player != null)
                {
                    player.MediaOpened -= OnOpened;
                    player.MediaEnded -= OnEnded;
                    player.MediaFailed -= OnFailed;
                    player.Close();
                }
            }
            catch (Exception ex)
            {
                if (error.Length == 0)
                    error = ex.Message;
                finalState = "Failed";
            }
            finally
            {
                player = null;
                Active.Remove(this);
                errorMessage = error;
                state = finalState;
            }
        }
    }
}
