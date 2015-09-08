
SET QUOTED_IDENTIFIER ON 
GO
SET ANSI_NULLS ON 
GO
CREATE PROCEDURE [dbo].[Task_Microgaming_Bettrans14] 
	@Fromdate	DATE
	, @Todate	DATE 
AS
/*
	 Creator: 20150731@Florent
	 Task: Generate data for MicroGaming from bettrans14
	 DB: DBLIC/bodb_LicenseeReport
	 Revisions: 		
	 Param's Explanation:
*/

BEGIN
	SET NOCOUNT ON
	IF @Fromdate IS NULL OR @Todate IS NULL
		RETURN	
	IF NOT EXISTS(SELECT TOP 1 1 FROM bodb02.dbo.bettrans14 WITH (NOLOCK)
				WHERE winlostdate BETWEEN @Fromdate AND @Todate	)
		RETURN
	
	DECLARE @Winlostdate DATE
	SET @Winlostdate = @Fromdate

	--bettype mapping
	DECLARE @Bettype AS TABLE(Bettype INT)
    INSERT INTO @Bettype (Bettype)
    SELECT Bettype
	FROM bodb_licensee.dbo.Sport_Bettype_Reference WITH (NOLOCK)
	WHERE Sporttype = 203 
	
	WHILE (@Winlostdate <= @Todate)
	BEGIN
		IF EXISTS (SELECT TOP 1 1 FROM dbo.rpt_ThirdPartyWL_ExtraGMT WITH (NOLOCK) WHERE RptDate = @Winlostdate)
		BEGIN
			DELETE dbo.rpt_ThirdPartyWL_ExtraGMT WITH (ROWLOCK, UPDLOCK) WHERE RptDate = @Winlostdate
		END

		INSERT INTO dbo.rpt_ThirdPartyWL_ExtraGMT(RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm)
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
			, SUM(b.playercomm) AS PComm		
		FROM bodb02.dbo.bettrans14 b WITH (NOLOCK)
			INNER JOIN @Bettype bt ON b.bettype = bt.Bettype
			LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
			LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
			LEFT JOIN bodb_licensee.dbo.view_site_list [site] (NOLOCK) ON s.siteid = site.IbcSiteID
		WHERE b.winlostdate = @Winlostdate		
			AND b.statusID NOT IN (0, 1, 101, 102, 121)
		GROUP BY CAST(b.winlostdate AS DATE), CAST(b.checktime AS DATE), ISNULL(site.SiteID,-1), b.bettype
		, b.currency, b.statusID
		OPTION (MAXDOP 1)

		SET @Winlostdate = DATEADD(D, 1, @Winlostdate)
	END
END


GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
