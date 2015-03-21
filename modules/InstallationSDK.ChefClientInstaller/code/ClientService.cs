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
        /// <param name="terminateOnFailure">Should the process terminate the processes of the Client service if it failes to stop in alloted time.</param>
        public static void Stop(bool terminateOnFailure)
        {
            Stop(new TimeSpan(0, 1, 0), terminateOnFailure);
        }

        /// <summary>
        /// Stop the Chef Client windows service.
        /// </summary>
        /// <param name="timeToWait">Wait time for operation to complete.</param>
        /// <param name="terminateOnFailure">Should the process terminate the processes of the Client service if it failes to stop in alloted time.</param>
        public static void Stop(TimeSpan timeToWait, bool terminateOnFailure)
        {
            var service = new WindowsService() { Name = "chef-client", TerminateOnFailure = terminateOnFailure, TimeToWait = timeToWait };
            service.Stop();
        }

        /// <summary>
        /// Start Chef Client windows service. 
        /// </summary>
        public static void Start()
        {
            Start(new TimeSpan( 0, 1, 0) );
        }

        /// <summary>
        /// Start Chef Client windows service. 
        /// </summary>
        public static void Start(TimeSpan timeToWait)
        {
            RoleEnvironment.Changing += ChefConfigChanging;
            RoleEnvironment.StatusCheck += Chef_StatusCheck;

            // Start Chef Client - wait 30 seconds
            var service = new WindowsService() { Name = "chef-client", TimeToWait = timeToWait };
            service.Start();
            ClientService.statusCheckFilePath = CloudConfigurationManager.GetSetting("ChefClient_SetBusyCheck");
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
                Stop(new TimeSpan(0, 0, 30), true);
                e.Cancel = true;
            }
        }
    }
}
