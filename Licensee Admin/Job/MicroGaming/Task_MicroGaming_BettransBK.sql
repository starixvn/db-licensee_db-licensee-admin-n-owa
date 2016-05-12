
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO

/****** Object:  Stored Procedure dbo.Task_MicroGaming_BettransBK    Script Date: 07/09/2015 10:07:30 AM ******/

CREATE PROCEDURE [dbo].[Task_MicroGaming_BettransBK] 
	@FromDate DATE
	, @ToDate DATE
AS
/*   
	Creator: 20150731@Florent
	Task: Gen history data from bettrans_bk
	DB: DBRPT/bodb_report
	Revisions: 	
		- 20150930@Florent: support Microgaming RNG
	Param's Explanation:	
*/
BEGIN
	SET NOCOUNT ON

	IF @FromDate IS NULL OR @ToDate IS NULL
		RETURN

	--clean data from temp table
	DELETE FROM dbo.rpt_ThirdPartyWL_ExtraGMTTemp WITH(ROWLOCK)
	WHERE rptDate BETWEEN @FromDate AND @ToDate

	DECLARE @WinlostDate DATE
	SELECT	@WinlostDate = @FromDate

	DECLARE @sql VARCHAR(1024)	
	DECLARE @Sitelist AS TABLE (IbcSiteID INT, SiteID INT)	
	
	INSERT INTO @Sitelist (IbcSiteID, SiteID)
	SELECT IbcSiteID, SiteID
	FROM OPENQUERY(DBLIC, 'SELECT IbcSiteID, SiteID FROM bodb_licensee.dbo.view_site_list')	

	WHILE @WinlostDate <= @ToDate
	BEGIN
		--For Keno
		INSERT INTO dbo.rpt_ThirdPartyWL_ExtraGMTTemp(RptDate, RptDate3rd, SiteId, BetTypeId,CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm)
		(
			SELECT CAST(b.winlostdate AS DATE)	AS Rptdate
				, CAST(b.checktime AS DATE)	AS RptDate3rd
				, ISNULL(site.SiteID, -1) AS siteid
				, b.bettype	 AS BetTypeId			
				, b.currency
				, b.statusID
				, COUNT(1) AS BetCount
				, SUM(ABS(b.stake)) AS Turnover
				, SUM(winlost - actual_stake) AS Winloss
				, SUM(b.comm) AS AComm		
				, SUM(b.playercomm) AS pComm
			FROM bodb_archive.dbo.bettrans_bk b WITH (NOLOCK)			
				LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
				LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
				LEFT JOIN @Sitelist [site] ON s.siteid = site.IbcSiteID				
			WHERE b.winlostdate = @WinlostDate
				AND b.bettype BETWEEN 2001 AND 2007	
				AND b.statusID NOT IN (0, 1, 101, 102, 121)	
			GROUP BY CAST(b.winlostdate AS DATE), ISNULL(site.SiteID, -1), CAST(b.checktime AS DATE), b.bettype
				, b.currency, b.statusID
			UNION
			SELECT CAST(b.winlostdate AS DATE)	AS Rptdate
				, CAST(b.Transdate3rd AS DATE)	AS RptDate3rd
				, ISNULL(site.SiteID, -1) AS siteid
				, b.gameID	 AS BetTypeId		
				, b.currency
				, b.statusID
				, COUNT(1) AS BetCount
				, SUM(ABS(b.stake)) AS Turnover
				, SUM(winlost - actual_stake) AS Winloss		
				, SUM(b.comm) AS AComm
				, SUM(b.playercomm) AS PComm
			FROM bodb_archive.dbo.bettransRnG_bk b WITH (NOLOCK)				
				LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
				LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
				LEFT JOIN @Sitelist [site] ON s.siteid = site.IbcSiteID			
			WHERE b.winlostdate = @WinlostDate
				AND b.gameID BETWEEN 2008 AND 2009
				AND b.statusID NOT IN (0, 1, 101, 102, 121)
			GROUP BY CAST(b.winlostdate AS DATE), CAST(b.Transdate3rd AS DATE), ISNULL(site.SiteID,-1), b.gameID
				, b.currency, b.statusID
		)
		OPTION (MAXDOP 1)
	
		--reset params		
		SET @WinlostDate = DATEADD(D, 1, @WinlostDate)

		WAITFOR DELAY '00:00:00.280'
	
	END		
END


GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[Task_MicroGaming_BettransBK] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[Task_MicroGaming_BettransBK] TO [bodbAdminNet]
GO 
