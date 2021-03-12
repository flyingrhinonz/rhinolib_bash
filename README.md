rhinolib bash library
=====================

Copyright (C) 2021 Kenneth Aaron.

flyingrhino AT orcon DOT net DOT nz

Freedom makes a better world: released under GNU GPLv3.

https://www.gnu.org/licenses/gpl-3.0.en.html

This software can be used by anyone at no cost, however, if you like using my software and can support - please donate money to a children's hospital of your choice.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation: GNU GPLv3. You must include this entire text with your distribution.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.


Manual install instructions
---------------------------

Copy: rhinolib.sh to: /usr/local/lib/
Use the file: script_template.sh as an example how to create your own scripts.


Usage
-----

The star of the show here is LogWrite function that provides proper logging from your script:
- Logging using standard syslog calls.
- You can log to regular /var/log/syslog file or any other file by configuring syslog to act upon the value of variable SyslogProgName.
- Splits long lines and marks them as such.
- Indents subsequent lines in an attempt to make the log file more readable.
- Logging at different log levels so you can easily switch from development to production by simply reducing the log level.

Captures crashes in your script and logs debugging information - making troubleshooting your scripts much easier.

Enjoy...


