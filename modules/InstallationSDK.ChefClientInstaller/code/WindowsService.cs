// --------------------------------------------------------------------------------------------------------------------
// <copyright file="WindowsService.cs" company="Microsoft Corporation">
//   Copyright (C) Microsoft. All rights reserved.
// </copyright>
// --------------------------------------------------------------------------------------------------------------------
namespace Microsoft.OnlinePublishing.Chef
{
    using System;
    using System.Diagnostics;
    using System.ServiceProcess;
    using System.Management;

    /// <summary>
    /// Windows Service gives the ability to stop a windows service (namely chef-client). 
    /// If the service failes to stop in a given timespan, then the service and its child processes are terminated.
    /// </summary>
    class WindowsService
    {
        /// <summary>
        /// Gets or sets the Name of the Windows Service.
        /// </summary>
        public string Name { get; set; }

        /// <summary>
        /// Gets or sets the alloted time to wait during shutdown sequence.
        /// </summary>
        public TimeSpan TimeToWait { get; set; }

        /// <summary>
        /// Gets or sets whether or not to terminate processes upon failure to stop teh service in the alloted time to wait.
        /// </summary>
        public bool TerminateOnFailure { get; set; }

        /// <summary>
        /// Start Chef Client windows service. 
        /// </summary>
        public void Start()
        {
            try
            {
                // Start Chef Client - wait 30 seconds
                Trace.TraceInformation("{0} - Attempting to start {0}.", Name);
                using (var chefService = new ServiceController(Name))
                {
                    if (chefService != null && chefService.Status != ServiceControllerStatus.Running)
                    {
                        chefService.Start();
                        chefService.WaitForStatus(ServiceControllerStatus.Running, TimeToWait);
                        Trace.TraceInformation("{0} - {0} Started.", Name);
                    }
                    else
                    {
                        Trace.TraceInformation("{0} - {0} previously running.", Name);
                    }
                }
            }
            catch (System.ServiceProcess.TimeoutException)
            {
                Trace.TraceInformation("{0} - failed to start Chef Client within time range.", Name);
            }
            catch (InvalidOperationException e)
            {
                Trace.TraceInformation("{0} - Invalid Operation, is the role running with elevated privileges. Ex:{1}.", Name, e.ToString());
            }
        }

        /// <summary>
        /// Stop the Windows Service, if Terminate on Failure, then terminate process and all child spawn.
        /// </summary>
        public void Stop()
        {
            try
            {
                // Stop Chef Client 
                Trace.TraceInformation("{0} - attempting to stop the {0} windows service.", Name);
                using (var chefService = new ServiceController(Name))
                {
                    if (chefService != null && chefService.Status != ServiceControllerStatus.Stopped)
                    {
                        chefService.Stop();
                        chefService.WaitForStatus(ServiceControllerStatus.Stopped, TimeToWait);
                        Trace.TraceInformation("{0} - {0} windows service Stopped.", Name);
                    }
                    else
                    {
                        Trace.TraceInformation("{0} - {0} windows service is not running.", Name);
                    }
                }
            }
            catch (System.ServiceProcess.TimeoutException)
            {
                Trace.TraceInformation("{0} - failed to stop {0} in time allotted [{1}].", Name, TimeToWait);
                if (TerminateOnFailure)
                {
                    Trace.TraceInformation("{0} - attempting to terminate service process and its children.", Name);
                    KillService();
                }
            }
            catch (InvalidOperationException e)
            {
                Trace.TraceInformation("{0} - Invalid Operation, is the role running with elevated privileges. Ex:{1}.", Name, e.ToString());
            }
        }

        /// <summary>
        /// Locate process by service name and kill it and its spawn.
        /// </summary>
        private void KillService()
        {
            var searcher = new ManagementObjectSearcher(
                "SELECT * " +
                "FROM Win32_Service " +
                "WHERE Name=\"" + Name + "\"");
            var collection = searcher.Get();
            foreach (var item in collection)
            {
                var serviceProcessId = (UInt32)item["ProcessId"];
                KillSpawnedProcesses(serviceProcessId);
                Trace.TraceInformation("{0} - Killing Service process with Id [{1}].", Name, serviceProcessId);
                KillProcess(serviceProcessId);
            }
        }

        /// <summary>
        /// Kill process and all spawn. Travers all children for multi generation children.
        /// </summary>
        /// <param name="parentProcessId">Parent ID</param>
        private void KillSpawnedProcesses(UInt32 parentProcessId)
        {
            Trace.TraceInformation("{0} - Finding processes spawned by process with Id [" + parentProcessId + "]", Name);

            var searcher = new ManagementObjectSearcher(
                "SELECT * " +
                "FROM Win32_Process " +
                "WHERE ParentProcessId=" + parentProcessId);
            var collection = searcher.Get();
            if (collection.Count > 0)
            {
                Trace.TraceInformation("{0} - Killing [{1}] processes spawned by process with Id [{2}].", Name, collection.Count, parentProcessId);
                foreach (var item in collection)
                {
                    var childProcessId = (UInt32)item["ProcessId"];
                    KillSpawnedProcesses(childProcessId);
                    KillProcess(childProcessId);
                }
            }
        }

        /// <summary>
        /// Attempt to kill process. It can ocurr that the process has been killed prior to getting to this statement as the process tree is being killed.
        /// </summary>
        /// <param name="processId">ID of process to kill.</param>
        private void KillProcess(uint processId)
        {
            try
            {
                if ((int)processId != Process.GetCurrentProcess().Id)
                {
                    var process = Process.GetProcessById((int)processId);
                    Trace.TraceInformation("{0} - Killing process [{1}] with Id [{2}]", Name, process.ProcessName, processId);
                    process.Kill();
                }
            }
            catch (ArgumentException e)
            {
                Trace.TraceInformation("{0} - failed to find process [{1}]. Process already killed. Ex:{2}", Name, processId, e.ToString());
            }
            catch (System.ComponentModel.Win32Exception e)
            {
                Trace.TraceInformation("{0} - failed to kill process [{1}]. Ex:{2}", Name, processId, e.ToString());
            }
        }
    }
}