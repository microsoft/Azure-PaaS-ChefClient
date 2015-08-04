# Azure-PaaS-ChefClient

##Overview
What is the **Azure PaaS/Chef Client bootstrapper**?

The Chef PaaS client was built out of a need to quickly establish a Chef client on a Azure PaaS Role. With this project, you can now easy create a Chef node on a PaaS role as easy as adding a Web or Worker Role and including the NuGet package that this generated from this project. 

You can also search [Nuget.Org -- To be Released](http://www.nuget.org/packages/) for the latest released package or you can clone the project source here.


##Using the Azure PaaS Chef Client

##Project Contents
The contents of this project is maintained in two dependent PowerShell Modules, the breakdown of the project:

- Core - module entry point scripts
- Modules
	- InstallationSDK.AzureServiceRuntime (PowerShell Module:Azure Service runtime wrapper) 
	- InstallationSDK.ChefClientInstaller (PowerShell Module:Configuration and Installation of the Chef Client)
		- code - .Net c# files
		- resource - place holder for adding the [Chef Client msi](http://www.opscode.com/chef/install.msi)
		- script - main PowerShell script for configuring the Chef Client
- NuGet - NuGet specifications for the two Module Packages

###Creating the Packages
To create the client NuGet package(s), [clone](github-windows://openRepo/https://github.com/Microsoft/Azure-PaaS-ChefClient) or [download](https://github.com/Microsoft/Azure-PaaS-ChefClient/archive/merge-code.zip) the project repository.

Using NuGet.exe, open a command window and navigate to the NuGet folder.

For example, my repositories are located in: 
```
c:\github\
```

Create the core package: 
```
C:\github\Azure-PaaS-ChefClient\nuget>nuget pack InstallationSDK.nuspec
```

Create the client installer package:
```
C:\github\Azure-PaaS-ChefClient\nuget>nuget pack InstallationSDK.ChefClientInstaller.nuspec
```

Now you have a local copy of the NuGet packages and can add them to your Cloud Service project in Visual Studio.

###Add to Cloud Service
Create a simple Cloud Service, add an empty Web Role, and open via solution context menu, 'Manage NuGet Packages for Solution'.

Configured for local package sources (where your newly packages reside), click 'install' to add the ChefClient package and select the WebRole that you wish to add it to. This will add both Chef Client and dependent Core packages to your solution package cache and project. 

Your web role will now contain the two code (.cs) files and a deployment folder with the configuration, script, and two PowerShell Modules.

###Configuration
There are two configuration paths to take, from config.json or directly in your cloud service configuration (.cscfg) file. They are limited based on the current functionality of the (script) main.ps1, but can be extended (read further below in *Extending*). These help in altering your client.rb during deployment time to transform your client.rb if needed, if not just include the desired client.rb for your Azure deployment of your cloud service. If you do employ one of these additional configuration steps, the client.rb will be augmented with the additional settings in the client.json or cloudservice.cscfg (yielding precedence to the cscfg data). 

####config.json
~~~json
{
  "name": "node_name_prefix",
  "environment": "chef_environment",
  "role": "chef_role_name",
  "pollInterval": "180",
  "serverUrl": "https://manage.chef.io/organizations/myorg",
  "sslVerifyMode": ":verify_peer",
  "validationClientName": "myorg-validator",
  "validationKey": "myorg-validator.pem",
  "encrypted_data_bag_secret_file": "encrypted_data_bag_secret"
}
~~~

####cloudService.cscfg
```xml
<ConfigurationSettings>
  <!-- Chef Settings -->
  <Setting name="ChefClient_ServerUrl" value="https://manage.chef.io/organizations/myorg" />
  <Setting name="ChefClient_Role" value="chef_role_name" />
  <Setting name="ChefClient_Environment" value="chef_environment" />
  <Setting name="ChefClient_Region" value="azure_region_name" />
  <Setting name="ChefClient_Function" value="azure_function_eg_production_or_test" />
  <Setting name="ChefClient_ServiceName" value="cloud_service_name" />
  <Setting name="ChefClient_Name" value="nade_name_prefix" />
</ConfigurationSettings>
```

##Data available to your recipes
Written to the Node at #[Node][Azure] are the following data elements and configured details, not limited to:
~~~ruby
deployment.id
update_domain
instance_id
fault_domain
instance_endpoints

chef_environment
chef_role
region
function
service_name
~~~

The last five, come directly from your configured service deployment allowing to pass from azure role to Chef Node.


###Extending
The ./deployment/script file [main.ps1]() can be altered in this location to meet your *more specific* needs if necessary, utilizing the Modules exported functions or additional ones you add to your project.

----------
##License
The MIT License (MIT)

Copyright (c) 

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

----------



