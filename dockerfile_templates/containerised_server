FROM dart:stable AS build


COPY . .
RUN dart pub get
RUN dart compile exe ./lib/server.dart -o ./bin/server

# Build minimal serving image from AOT-compiled `/server` and required system
# libraries and configuration files stored in `/runtime/` from the build stage.
FROM gcr.io/distroless/base
COPY --from=build /runtime/ /
COPY --from=build /root/bin/server ./server

EXPOSE 8080

CMD [ "./server" ]