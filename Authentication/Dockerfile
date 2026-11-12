FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY global.json Directory.Build.props ./
COPY ServerLogging/ ServerLogging/
COPY Authentication/ Authentication/
RUN dotnet restore Authentication/FitnessTracker.Authentication.csproj --locked-mode
RUN dotnet publish Authentication/FitnessTracker.Authentication.csproj -c Release --no-restore -o /out

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /out .
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgssapi-krb5-2 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir /app/keys && chown $APP_UID /app/keys
USER $APP_UID
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "FitnessTracker.Authentication.dll"]
