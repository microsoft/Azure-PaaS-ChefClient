// --------------------------------------------------------------------------------------------------------------------
// <copyright file="ClientService.cs" company="Microsoft Corporation">
//   Copyright (C) Microsoft. All rights reserved.
// </copyright>
// --------------------------------------------------------------------------------------------------------------------
namespace Microsoft.OnlinePublishing.Chef
{
    using Microsoft.WindowsAzure;
    using Microsoft.WindowsAzure.ServiceRuntime;
    using System;
    using System.Diagnostics;
    using System.Linq;
    using System.ServiceProcess;

    /// <summary>
    /// The Chef.ClientService Start and Stop methods should be called in the Roles OnStart and OnStop methods respectively.
    /// </summary>
    public static class ClientService
    {
        /// <summary>
        /// Path to find the status check file for determining if instance should be busy
        /// </summary>
        private static string statusCheckFilePath;

        /// <summary>
        /// Stop the Chef Client windows service with the default wait time of 1 minute.
        /// </summary>
        public static void Stop()
        {
            Stop(new TimeSpan(0, 1, 0));
        }

        /// <summary>
        /// Stop the Chef Client windows service.
        /// </summary>
        /// <param name="timeToWait">Wait time for operation to complete.</param>
        public static void Stop(TimeSpan timeToWait)
        {
            try
            {
                // Stop Chef Client 
                Trace.TraceInformation("Chef Client - attempting to stop the Chef Client windows service.");
                using (var chefService = new ServiceController("chef-client"))
                {
                    if (chefService != null && chefService.Status != ServiceControllerStatus.Stopped)
                    {
                        chefService.Stop();
                        chefService.WaitForStatus(ServiceControllerStatus.Stopped, timeToWait);
                        Trace.TraceInformation("Chef Client - Chef Client windows service Stopped.");
                    }
                    else
                    {
                        Trace.TraceInformation("Chef Client - Chef Client windows service is not running.");
                    }
                }
            }
            catch (System.ServiceProcess.TimeoutException)
            {
                Trace.TraceInformation("Chef Client - failed to stop Chef Client in time allotted [{0}].", timeToWait);
            }
            catch (InvalidOperationException e)
            {
                Trace.TraceInformation("Chef Client - Invalid Operation, is the role running with elevated privileges. Ex:{0}.", e.ToString());
            }
        }

        /// <summary>
        /// Start Chef Client windows service. 
        /// </summary>
        public static void Start()
        {
            try
            {
                RoleEnvironment.Changing += ChefConfigChanging;
                RoleEnvironment.StatusCheck += Chef_StatusCheck;

                // Start Chef Client - wait 30 seconds
                Trace.TraceInformation("Chef Client - Attempting to start Chef-Client.");
                using (var chefService = new ServiceController("chef-client"))
                {
                    if (chefService != null && chefService.Status != ServiceControllerStatus.Running)
                    {
                        chefService.Start();
                        chefService.WaitForStatus(ServiceControllerStatus.Running, new TimeSpan(0, 0, 30));
                        Trace.TraceInformation("Chef Client - Chef-Client Started.");
                    }
                    else
                    {
                        Trace.TraceInformation("Chef Client - Chef-Client previously running.");
                    }
                }

                ClientService.statusCheckFilePath = CloudConfigurationManager.GetSetting("ChefClient_SetBusyCheck");
            }
            catch (System.ServiceProcess.TimeoutException)
            {
                Trace.TraceInformation("Chef Client - failed to start Chef Client within time range.");
            }
            catch (InvalidOperationException e)
            {
                Trace.TraceInformation("Chef Client - Invalid Operation, is the role running with elevated privileges. Ex:{0}.", e.ToString());
            }
        }

        /// <summary>
        /// Handle Azure status check events to set the role as busy if the lock file is missing.
        /// </summary>
        /// <param name="sender">Sender object</param>
        /// <param name="e">Event arguments</param>
        static void Chef_StatusCheck(object sender, RoleInstanceStatusCheckEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(ClientService.statusCheckFilePath) || 
                System.IO.File.Exists(ClientService.statusCheckFilePath))
            {
                return;
            }
            e.SetBusy();
        }

        /// <summary>
        /// Handle configuration change events for ChefClient_ServerURL, ChefClient_Role, or ChefClient_Environment. 
        /// This will cancel the event and force a Role Restart so that the client scripts (main.ps1) will reset a new 
        /// connection and client registration with the new Server.
        /// </summary>
        /// <param name="sender">Sender object</param>
        /// <param name="e">Event arguments</param>
        private static void ChefConfigChanging(object sender, RoleEnvironmentChangingEventArgs e)
        {
            var configurationChanges = e.Changes.OfType<RoleEnvironmentConfigurationSettingChange>().ToList();

            if (!configurationChanges.Any()) return;

            if (configurationChanges.Any(c => c.ConfigurationSettingName == "ChefClient_SetBusyCheck"))
            {
                ClientService.statusCheckFilePath = CloudConfigurationManager.GetSetting("ChefClient_SetBusyCheck");
            }

            if (configurationChanges.Any(c => c.ConfigurationSettingName == "ChefClient_ServerUrl" || 
                c.ConfigurationSettingName == "ChefClient_Role" || 
                c.ConfigurationSettingName == "ChefClient_Environment" ))
            {
                Stop(new TimeSpan(0, 0, 5));
                e.Cancel = true;
            }
        }
    }
}
