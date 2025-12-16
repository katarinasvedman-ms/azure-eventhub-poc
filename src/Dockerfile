FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY ["LogsysNgPoC.csproj", "."]
RUN dotnet restore "LogsysNgPoC.csproj"

COPY . .
RUN dotnet build "LogsysNgPoC.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "LogsysNgPoC.csproj" -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=publish /app/publish .
EXPOSE 5000 5001
ENTRYPOINT ["dotnet", "LogsysNgPoC.dll"]
