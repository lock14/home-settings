# Ubuntu Setup Script
The script ubuntu\_18.04+\_setup.sh is intended to get a java workflow setup on a fresh ubuntu intall. The script does the following:
- Updates Ubuntu to the latest packages
- installs git
- installs vim
- installs curl
- installs Google Chrome
- installs a JDK (JDK 11 by default)
- installs maven
- installs mariadb
- installs a Java IDE (IntelliJ Idea Ultiamte by default)
- installs VS Code
- installs Postman
- installs Slack

## Script Options
* -j: specify the JDK you would like, valid choices are: 'openjdk-8', 'openjdk-11'. If none is selected then 'openjdk-11' is chosen by default.
* -i: specify the Java IDE you would like, valid choices are: 'intellij', 'intellij-ultimate', 'eclipse', 'netbeans'. If none is selected then 'intellij-ultimate' is chosen by default.
