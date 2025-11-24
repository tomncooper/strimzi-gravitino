# Runtime-only Dockerfile for Product Recommendation Kafka Streams App
# Assumes JAR is already built on host via: mvn clean package

FROM eclipse-temurin:17-jre-ubi10-minimal

RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app

# Copy the pre-built uber JAR from host
COPY target/product-recommendation-*.jar /app/product-recommendation.jar

# Change ownership to app user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Set default JVM options
# Note: JAVA_OPTS can be overridden via environment variables in Kubernetes
# JAVA_TOOL_OPTIONS is also automatically picked up by the JVM
ENV JAVA_OPTS="-Xms512m -Xmx2g \
    -XX:+UseG1GC \
    -XX:MaxGCPauseMillis=200 \
    -Djava.security.egd=file:/dev/./urandom"

# Run the application
# The shell expansion of $JAVA_OPTS allows environment variable override
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/product-recommendation.jar"]
