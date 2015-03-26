USE [bodb_report]
GO

/****** Object:  StoredProcedure [dbo].[Task_KenoWinloss_GenDataFromBettransBK]    Script Date: 05/03/2015 16:14:46 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/****** Object:  Stored Procedure dbo.Task_KenoWinloss_GenDataFromBettransBK    Script Date: 05/03/2015 15:08:27 PM ******/
CREATE PROCEDURE [dbo].[Task_KenoWinloss_GenDataFromBettransBK] 
	@FromDate DATE
	, @ToDate DATE
AS
/*   
 Creator: 20150304@Florent
 Task: Gen history data from bettrans_bk
 DB: DBACC/bodb_LicenseeReport
 Revisions: 
	- 20150323@Florent: remove void, reject ticket
 Param's Explanation:	
*/
BEGIN
	SET NOCOUNT ON

	IF @FromDate IS NULL OR @ToDate IS NULL
		RETURN

	--clean data from temp table
	DELETE FROM dbo.rptKenoWinlosstmp WITH(ROWLOCK)
	WHERE rptDate BETWEEN @FromDate AND @ToDate

	DECLARE @WinlostDate DATE
	SELECT	@WinlostDate = @FromDate

	DECLARE @sql VARCHAR(1024)
	DECLARE @KenoBettypeMapping AS TABLE (BettypeID INT, ChoiceId INT)
	DECLARE @Sitelist AS TABLE (IbcSiteID INT, SiteID INT)
	
	INSERT INTO @KenoBettypeMapping (BettypeID, ChoiceId)
	SELECT BettypeID, ChoiceID
	FROM OPENQUERY(DBEXT, 'SELECT DISTINCT BettypeID, ChoiceID FROM bodb02.dbo.View_KenoBettypeMapping')

	INSERT INTO @Sitelist (IbcSiteID, SiteID)
	SELECT IbcSiteID, SiteID
	FROM OPENQUERY(DBLIC, 'SELECT IbcSiteID, SiteID FROM bodb_licensee.dbo.view_site_list')	

	WHILE @WinlostDate <= @ToDate
	BEGIN
		--For Keno
		INSERT INTO dbo.rptKenoWinlossTmp(RptDate, SiteId, BetTypeId, KenoBetTypeId, ChoiceId, CurrencyId, StatusId, BetCount, Turnover, Winloss)
		SELECT CAST(b.winlostdate AS DATE)	AS Rptdate
			, ISNULL(site.SiteID, -1) AS siteid
			, b.bettype	 AS BetTypeId
			, v.BettypeID AS KenoBetTypeId
			, p.ChoiceId AS ChoiceId
			, b.currency
			, b.statusID
			, COUNT(1) AS BetCount
			, SUM(ABS(b.stake)) AS Turnover
			, SUM(winlost - actual_stake) AS Winloss		
		FROM bodb_archive.dbo.bettrans_bk b WITH (NOLOCK)			
			LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
			LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
			LEFT JOIN @Sitelist [site] ON s.siteid = site.IbcSiteID	
			CROSS APPLY bodb02.dbo.f_ParseTransDesc(b.transdesc, b.bettype) p
			LEFT JOIN @KenoBettypeMapping v ON p.ChoiceId = v.ChoiceId
		WHERE b.winlostdate = @WinlostDate
			AND b.bettype BETWEEN 1501 AND 1599	
			AND b.statusID NOT IN (0, 1, 101, 102, 121)	
		GROUP BY CAST(b.winlostdate AS DATE), ISNULL(site.SiteID, -1), b.bettype
			, p.ChoiceId, v.BettypeID,  b.currency, b.statusID
		OPTION (MAXDOP 1)
	
		--reset params		
		SET @WinlostDate = DATEADD(D, 1, @WinlostDate)

		WAITFOR DELAY '00:00:00.280'
	
	END		
END
GO
GRANT VIEW DEFINITION ON [dbo].[Task_KenoWinloss_GenDataFromBettransBK] TO [vnteam] 