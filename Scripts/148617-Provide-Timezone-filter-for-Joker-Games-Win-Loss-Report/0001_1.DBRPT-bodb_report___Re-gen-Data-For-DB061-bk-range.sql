/*<info serverAlias="DBRPT-bodb_report"></info>*/
/*   
	Creator: 20210113@Parsons
	Task:   Generate data of Joker for 2020-11-12 -> Now [#FeatureID 148617]
	DB:	    DBRPT-bodb_report
	Remark:	Re-gen data for Joker - range bettrans_bk
*/

USE bodb_report
GO

DECLARE	
		@FromDate DATE = '2020-11-12', 
		@ToDate DATE = '2020-12-31' -- Current BU Date - 1 (BU = 2021-01-01)

BEGIN
	DECLARE @ErrMsg VARCHAR(200)

	DECLARE @WinlostDate DATE
	SELECT	@WinlostDate = @FromDate

	DECLARE @Sitelist TABLE (IbcSiteID INT, SiteID INT)	
	INSERT INTO @Sitelist (IbcSiteID, SiteID)
	SELECT IbcSiteID, SiteID
	FROM bodb_Licensee.dbo.view_site_list WITH (NOLOCK)	
	
	WHILE @WinlostDate <= @ToDate
	BEGIN
		SELECT @ErrMsg = 'WinlostDate=' + CONVERT(VARCHAR(20), @WinlostDate, 120)
		RAISERROR(@ErrMsg, 1, 0) WITH NOWAIT

		DELETE FROM dbo.rpt_ThirdPartyWL_ExtraGMT WITH(ROWLOCK)
		WHERE rptDate = @WinlostDate
			AND BetTypeId BETWEEN 6401 AND 6700 -- JK
		
		INSERT INTO dbo.rpt_ThirdPartyWL_ExtraGMT(RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm, AWinloss, ProgressiveContribution, ProgressivePayout,ValidBetAmount)
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
			, SUM(b.awinlost) AS AWinloss
			, 0 ProgressiveContribution
			, 0 AS ProgressivePayout
			, 0 AS ValidBetAmount 
		FROM bodb_Archive.dbo.bettransRnG_bk b WITH (NOLOCK)
			LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
			LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
			LEFT JOIN @Sitelist [site] ON s.siteid = site.IbcSiteID
		WHERE b.winlostdate = @Winlostdate
			AND b.statusID IN (111, 112, 113)
			AND b.gameID BETWEEN 6401 AND 6700 -- JK
		GROUP BY CAST(b.winlostdate AS DATE), CAST(b.Transdate3rd AS DATE), ISNULL(site.SiteID, -1), b.gameID
			, b.currency, b.statusID
				
		--reset params
		SET @WinlostDate = DATEADD(DAY, 1, @WinlostDate)

		WAITFOR DELAY '00:00:00.280'
	END	
END
GO