FROM quay.io/streamshub/flink-sql-runner:0.1.0

# Download Gravitino Flink connector and add it to Flink's lib directory
RUN wget -O /opt/flink/lib/gravitino-flink-connector-1.0.0.jar \
    https://repo1.maven.org/maven2/org/apache/gravitino/gravitino-flink-connector-runtime-1.18_2.12/1.0.1/gravitino-flink-connector-runtime-1.18_2.12-1.0.1.jar

# Download Flink JDBC connector and add it to Flink's lib directory
RUN wget  -O /opt/flink/lib/flink-connector-jdbc-3.2.0-1.18.jar \
    https://repo.maven.apache.org/maven2/org/apache/flink/flink-connector-jdbc/3.2.0-1.18/flink-connector-jdbc-3.2.0-1.18.jar

# Download PostgreSQL JDBC driver and add it to Flink's lib directory
RUN wget -O /opt/flink/lib/postgresql-42.7.8.jar \
    https://jdbc.postgresql.org/download/postgresql-42.7.8.jar

# Verify the jar was downloaded successfully
RUN ls -lh /opt/flink/lib/gravitino-flink-connector-1.0.0.jar
