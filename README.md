# Shells

This gem is a collection of shell classes that can be used to interact with various devices.
It started as a secure shell to interact with SSH hosts, then it received a shell to access pfSense devices.
A natural progression had me adding a serial shell and another shell to access pfSense devices over serial.

If you can't tell, it was primarily developed to interact with pfSense devices, but also tends to work well
for interacting with other devices and hosts as well.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'shells'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install shells


## Usage

Any of the various "Session" classes can be used to interact with a device or host.

```ruby
Shells::SshSession.new(host: 'my.device.name.or.ip', user: 'somebody', password: 'secret') do |sh|
  sh.exec "cd /usr/local/bin"
  user_bin_files = sh.exec("ls -A1").split("\n")
  @app_is_installed = user_bin_files.include?("my_app")
end
```

Every session constructor works the same way.  The shell is connected to, the prompt is set, and then the block
of code passed to the constructor is executed on the shell.  After the code block completes, the session is finalized
and the shell is closed.

The `Shells` module is designed to allow you to forego the `.new` as well.  So `Shells::SshSession(...)` is the same as 
`Shells::SshSession.new(...)`.

In most cases you will be sending commands to the shell using the `.exec` method of the shell passed to the code block.
The `.exec` method returns the output of the command and then you can process the results.  You can also request that 
the `.exec` method retrieves the exit code from the command as well, but this will only work in some shells.

```ruby
Shells::SshSession(host: 'my.device.name.or.ip', user: 'somebody', password: 'secret') do |sh|
  # By default shells do not retrieve exit codes or raise on non-zero exit codes.
  # These parameters can be set in the options list for the constructor as well to change the 
  # default behavior.
  
  # This command will execute the command and then retrieve the exit code.
  # We then perform an action based on the exit code.
  sh.exec "some command", retrieve_exit_code: true
  raise 'Some Error' if sh.last_exit_code != 0
  
  # This command will execute the command then automatically raise an error if the exit code
  # is non-zero.  The error raised is a Shells::NonZeroExitCode exception which happens to have
  # an exit_code property for your rescue code to examine.
  sh.exec "some command", retrieve_exit_code: true, on_non_zero_exit_code: :raise
end
```


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/barkerest/shells.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

