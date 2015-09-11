{
  :type => 'aio',
  :passenger => true,
  :pre_suite => [
    'setup/common/pre-suite/000-delete-puppet-when-sparc.rb',
    'setup/aio/pre-suite/010_Install.rb',
    'setup/passenger/pre-suite/015_PackageHostsPresets.rb',
    'setup/common/pre-suite/025_StopFirewall.rb',
    'setup/passenger/pre-suite/030_ConfigurePassenger.rb',
    'setup/common/pre-suite/040_ValidateSignCert.rb',
    'setup/aio/pre-suite/045_EnsureMasterStartedOnPassenger.rb',
    'setup/common/pre-suite/070_InstallCACerts.rb',
  ],
}
