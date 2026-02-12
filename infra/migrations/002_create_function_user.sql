-- Migration: Create contained SQL user for Function App managed identity
-- Run this after deploying the Function App (needs the MI to exist in AAD).

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'func-logsysng-eyeqfiorm5tv2')
BEGIN
    CREATE USER [func-logsysng-eyeqfiorm5tv2] FROM EXTERNAL PROVIDER;
    ALTER ROLE db_datareader ADD MEMBER [func-logsysng-eyeqfiorm5tv2];
    ALTER ROLE db_datawriter ADD MEMBER [func-logsysng-eyeqfiorm5tv2];
    PRINT 'Created user func-logsysng-eyeqfiorm5tv2 with db_datareader + db_datawriter';
END
ELSE
BEGIN
    PRINT 'User func-logsysng-eyeqfiorm5tv2 already exists';
END
GO
