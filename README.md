# check_logfiles
This plugins processes a logfile (-l) and report on all time taken entries for last (-m) minutes.

The scripts are a modification from https://exchange.nagios.org/directory/Plugins/Web-Servers/Apache/check_access_log-2Epl/details

## check_Tomcatlogfile.pl:
Processes a tomcat logfile with pattern "%a %t %H %p %U %s %S %D %I %b".

Alerts are sent if the time-taken max value exceeds the threshold, but it could be changed in order to evaluate another value, for example the average time of the interval (see line 209).

Example: check_tomcatlogfile.pl -fp "/usr/tomcat/apache-tomcat-6.0.29/logs" -pl "tomcat_access_" -sl ".log" -r "/newResource/index.html" -w 2000 -c 5000 -m 5

## check_iislogfile.pl
Processes an iis logfile with logging fields like in the next image.

![alt tag](https://raw.githubusercontent.com/abstracta/check_logfiles/master/iisPattern.png)

Alerts are sent if the time-taken max value exceeds the threshold, but it could be changed in order to evaluate another value, for example the average time of the interval (see line 203).

Example: check_iislogfile.pl -f C:\WINDOWS\system32\LogFiles\W3SVC1 -p u_ex -s .log -r /Default.aspx -m 1000 -w 1000 -c 5000