using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace MetricSysPoC.Middleware;

/// <summary>
/// Middleware for API authentication and authorization.
/// Currently validates Bearer token from Authorization header.
/// Can be extended to use Azure AD, OAuth2, or other auth providers.
/// </summary>
public class AuthenticationMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<AuthenticationMiddleware> _logger;
    private readonly string _apiKey;

    public AuthenticationMiddleware(RequestDelegate next, ILogger<AuthenticationMiddleware> logger, IConfiguration configuration)
    {
        _next = next;
        _logger = logger;
        _apiKey = configuration["ApiKey"] ?? throw new InvalidOperationException("ApiKey not configured");
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Skip authentication for health check endpoints
        if (context.Request.Path.StartsWithSegments("/health"))
        {
            await _next(context);
            return;
        }

        // Require authorization header
        if (!context.Request.Headers.TryGetValue("Authorization", out var authHeader))
        {
            _logger.LogWarning("Request without Authorization header from {RemoteIP}", context.Connection.RemoteIpAddress);
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { error = "Authorization header missing" });
            return;
        }

        // Validate Bearer token
        const string bearerScheme = "Bearer ";
        if (!authHeader.ToString().StartsWith(bearerScheme))
        {
            _logger.LogWarning("Invalid Authorization header format from {RemoteIP}", context.Connection.RemoteIpAddress);
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid Authorization header format" });
            return;
        }

        var token = authHeader.ToString()[bearerScheme.Length..];

        // Validate token against API key (in production: validate JWT, check Azure AD, etc.)
        if (!token.Equals(_apiKey, StringComparison.Ordinal))
        {
            _logger.LogWarning("Invalid API key from {RemoteIP}", context.Connection.RemoteIpAddress);
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid API key" });
            return;
        }

        _logger.LogDebug("Successfully authenticated request from {RemoteIP}", context.Connection.RemoteIpAddress);
        await _next(context);
    }
}

/// <summary>
/// Extension methods for authentication middleware.
/// </summary>
public static class AuthenticationMiddlewareExtensions
{
    public static IApplicationBuilder UseApiAuthentication(this IApplicationBuilder builder)
    {
        return builder.UseMiddleware<AuthenticationMiddleware>();
    }
}
