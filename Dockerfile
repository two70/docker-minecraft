FROM debian:stable as builder
RUN mkdir /build
WORKDIR /build
RUN apt update
RUN apt install bash ca-certificates wget git -y # install first to avoid openjdk install bug
RUN apt install openjdk-17-jre-headless -y
RUN wget -O BuildTools.jar https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar
RUN git config --global --unset core.autocrlf || exit 0
RUN java -jar BuildTools.jar --rev latest #change to specific version if you don't want latest STABLE release
RUN mv spigot-*.jar spigot.jar

FROM debian:stable
RUN apt update
RUN apt install openjdk-17-jre-headless bash -y
RUN mkdir /server /minecraft
RUN adduser --system --shell /bin/bash --group minecraft
COPY --from=builder --chown=minecraft:minecraft /build/spigot.jar /server
RUN chown -R minecraft:minecraft /server
RUN chown -R minecraft:minecraft /minecraft
USER minecraft
WORKDIR /minecraft
CMD ["java", "-Xms1G", "-Xmx1G", "-XX:+UseG1GC", "-jar", "/server/spigot.jar", "nogui"]
