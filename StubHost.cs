namespace System.Management.Automation.Internal.Host {
    using System;
    using System.Globalization;
    using System.Management.Automation.Host;
    
    public class SHost {
        private bool shouldExit;
        private int exitCode;
        public bool ShouldExit {
            get { return this.shouldExit; }
            set { this.shouldExit = value; }
        }
        public int ExitCode {
            get { return this.exitCode; }
            set { this.exitCode = value; }
        }
        private static void Main(string[] args) {
        }
    }

    public class StubHost : PSHost {
        private SHost program;
        private CultureInfo originalCultureInfo =
            System.Threading.Thread.CurrentThread.CurrentCulture;
        private CultureInfo originalUICultureInfo =
            System.Threading.Thread.CurrentThread.CurrentUICulture;
        private Guid instanceId = Guid.NewGuid();
        
        public StubHost() {}
        public StubHost(SHost program) {
            this.program = program;
        }
        public override CultureInfo CurrentCulture {
            get { return this.originalCultureInfo; }
        }
        public override CultureInfo CurrentUICulture {
            get { return this.originalUICultureInfo; }
        }
        public override Guid InstanceId {
            get { return this.instanceId; }
        }
        public override string Name {
            get { return "StubHost"; }
        }
        public override PSHostUserInterface UI {
            get { return null; }
        }
        public override Version Version {
            get { return new Version(1, 0); }
        }
        public override void EnterNestedPrompt() {
            throw new NotImplementedException(
                "The method or operation is not implemented.");
        }
        public override void ExitNestedPrompt() {
            throw new NotImplementedException(
                "The method or operation is not implemented.");
        }
        public override void NotifyBeginApplication() {
            return;  
        }
        public override void NotifyEndApplication() {
            return; 
        }
        public override void SetShouldExit(int exitCode) {
            this.program.ShouldExit = true;
            this.program.ExitCode = exitCode;
        }
    }
}