USE bodb_licensee
GO

ALTER PROCEDURE dbo.LA_PeakConcurrentUsersSel
	@PartyId INT,
	@FromDate DATETIME,
	@ToDate DATETIME
AS
/*	Created by: Bruce
	Date: 2016-06-13
	Task: Get peak concurrent users for Licensee
	DB: DB052.bodb_Licensee
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @ServerIds VARCHAR(1000) = (SELECT STUFF((
		SELECT ',', LEFT(s2.ServerID,3)
		FROM dbo.OAS_Party AS p WITH (NOLOCK)
		INNER JOIN dbo.view_site_list s1 WITH (NOLOCK) ON p.OldRefID = s1.SiteID
		INNER JOIN bodb02.dbo.[Site] s2 WITH (NOLOCK) ON s1.IbcSiteID = s2.SiteID
		WHERE p.PartyID = @PartyId
		FOR XML PATH('')), 1, 1, '')
	)
	
	IF(ISNULL(@ServerIds,'') = '')
	BEGIN
		SELECT TOP 0 
			CAST(0 AS INT) AS TotalUser,
			CAST(NULL AS DATETIME) AS LogDate
		RETURN
	END

	DECLARE @OpenQuery VARCHAR(2000) = '
		DECLARE @FromDate DATETIME = ''''' + CONVERT(VARCHAR(50), @FromDate, 120) +''''',
				@ToDate DATETIME = ''''' + CONVERT(VARCHAR(50), @ToDate, 120) +'''''

		;WITH OU AS (
			SELECT SUM(Users) Users, LogDate
			FROM ON_USER.dbo.TotalOnline WITH (NOLOCK)
			WHERE LEFT(ServerID,3) IN (' + @ServerIds +') AND LogDate BETWEEN @FromDate and @ToDate
			GROUP BY LogDate

			UNION ALL

			SELECT SUM(Users) Users, LogDate
			FROM ON_USER.dbo.TotalOnline_BK WITH (NOLOCK)
			WHERE LEFT(ServerID,3) IN (' + @ServerIds +') AND LogDate BETWEEN @FromDate and @ToDate
			GROUP BY LogDate
		)
		SELECT MAX(Users) AS TotalUser, DATEADD(d, DATEDIFF(DAY, 0, LogDate), 0) AS LogDate
		FROM OU
		GROUP BY DATEADD(d, DATEDIFF(DAY, 0, LogDate), 0)
		ORDER BY LogDate
	'

	EXEC('SELECT * FROM OPENQUERY(DBONUSER, ''' + @OpenQuery + ''')')
END