FROM bitnami/tomcat:latest
COPY target/SimpleTomcatWebApp.war /opt/bitnami/tomcat/webapps_default
