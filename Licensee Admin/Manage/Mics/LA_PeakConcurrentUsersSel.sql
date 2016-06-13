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
	DB: DB03.bodb_licensee
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Server TABLE(ServerID INT)

	INSERT INTO @Server (ServerID)
	(
		SELECT LEFT(s2.ServerID,3)
		FROM dbo.OAS_Party AS p WITH (NOLOCK)
		INNER JOIN dbo.view_site_list s1 WITH (NOLOCK) ON p.OldRefID = s1.SiteID
		INNER JOIN bodb02.dbo.[Site] s2 WITH (NOLOCK) ON s1.IbcSiteID = s2.SiteID
		WHERE p.PartyID = @PartyId
	)

	;WITH OU AS (
		SELECT SUM(Users) Users, LogDate
		FROM ON_USER.dbo.TotalOnline WITH (NOLOCK)
		WHERE LEFT(ServerID,3) IN (SELECT s.ServerID FROM @Server s) AND LogDate BETWEEN @FromDate and @ToDate
		GROUP BY LogDate

		UNION ALL

		SELECT SUM(Users) Users, LogDate
		FROM ON_USER.dbo.TotalOnline_BK WITH (NOLOCK)
		WHERE LEFT(ServerID,3) IN (SELECT s.ServerID FROM @Server s) AND LogDate BETWEEN @FromDate and @ToDate
		GROUP BY LogDate
	)
	SELECT MAX(Users) AS TotalUser, DATEADD(d, DATEDIFF(DAY, 0, LogDate), 0) AS LogDate
	FROM OU
	GROUP BY DATEADD(d, DATEDIFF(DAY, 0, LogDate), 0)
	ORDER BY LogDate

END