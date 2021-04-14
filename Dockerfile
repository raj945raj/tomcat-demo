FROM bitnami/tomcat:latest
COPY SimpleTomcatWebApp.war /opt/bitnami/tomcat/webapps_default
