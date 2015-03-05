USE [bodb_LicenseeReport]
GO

/****** Object:  StoredProcedure [dbo].[Task_KenoWinloss_GenDataFromBettrans14]    Script Date: 05/03/2015 16:13:18 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/****** Object:  Stored Procedure dbo.Task_KenoWinloss_GenDataFromBettrans14    Script Date: 05/03/2015 15:08:26 PM ******/
CREATE PROCEDURE [dbo].[Task_KenoWinloss_GenDataFromBettrans14] 
	@Fromdate	DATE
	, @Todate	DATE 
AS
/*
	 Creator: 20150209@Florent
	 Task: Generate data for Keno Winlost from bettrans14
	 DB: DBLIC/bodb_LicenseeReport
	 Revisions: 
	 Param's Explanation:
*/

BEGIN
	SET NOCOUNT ON
	IF @Fromdate IS NULL OR @Todate IS NULL
		RETURN	
	
	DECLARE @Winlostdate DATE
	SET @Winlostdate = @Fromdate

	--bettype mapping
	CREATE TABLE #Bettype (Bettype INT, ProductID INT)
    INSERT INTO #Bettype
    SELECT Bettype, ProductID 
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'KN')
	
	WHILE (@Winlostdate <= @Todate)
	BEGIN
		IF EXISTS (SELECT TOP 1 1 FROM dbo.rptKenoWinloss WITH (NOLOCK) WHERE RptDate = @Winlostdate)
		BEGIN
			DELETE dbo.rptKenoWinloss WITH (ROWLOCK, UPDLOCK) WHERE RptDate = @Winlostdate
		END
		--For Keno
		INSERT INTO dbo.rptKenoWinloss(RptDate, SiteId, BetTypeId, KenoBetTypeId, ChoiceId, CurrencyId, StatusId, BetCount, Turnover, Winloss)
		SELECT CAST(b.winlostdate AS DATE)	AS Rptdate
			, ISNULL(site.SiteID, -1) AS SiteId
			, b.bettype	 AS BetTypeId
			, ISNULL(v.BettypeID, -1) AS KenoBetTypeId
			, p.ChoiceId AS ChoiceId
			, b.currency
			, b.statusID
			, COUNT(1) AS BetCount
			, SUM(ABS(b.stake)) AS Turnover
			, SUM(winlost - actual_stake) AS Winloss		
		FROM bodb02.dbo.bettrans14 b WITH (NOLOCK)
			INNER JOIN #Bettype bt ON b.bettype = bt.Bettype
			LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
			LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
			LEFT JOIN bodb_licensee.dbo.view_site_list [site] (NOLOCK) ON s.siteid = site.IbcSiteID	
			CROSS APPLY bodb02.dbo.f_ParseTransDesc(b.transdesc, b.bettype) p
			LEFT JOIN bodb02.dbo.View_KenoBettypeMapping v ON p.ChoiceId = v.ChoiceId
		WHERE b.winlostdate = @Winlostdate			
		GROUP BY CAST(b.winlostdate AS DATE), ISNULL(site.SiteID, -1), b.bettype
			, p.ChoiceId, ISNULL(v.BettypeID, -1),  b.currency, b.statusID
		OPTION (MAXDOP 1)

		SET @Winlostdate = DATEADD(D, 1, @Winlostdate)
	END

	DROP TABLE #Bettype	
END
GO
GRANT VIEW DEFINITION ON [dbo].[Task_KenoWinloss_GenDataFromBettrans14] TO [vnteam] 


