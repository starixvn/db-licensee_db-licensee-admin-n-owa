/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_SabaPromotion]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20) = 'EUR',
	@IsShowWonLose		BIT = 0
AS
/*
 * Created by : [20191017@Mason.Nguyen]
 * Task  : Get Saba Promotion report
 * Revisions
	- 20191017@Mason: Saba Promotion [#119538]

 * Param's Explanation:
	* PartyIds: a string of list PartyID, separate by ','
	* BaseCurrencyName: GBP, CNY, USD, EUR, MYR
	* FromDate: Ex: '01-15-2019 00:00:00 AM'
	* FromDate: Ex: '01-30-2019 00:00:00 AM'
	* @IsShowWonLose: 'Won/Lose' filter is supportted (0: Show reports with all tickets, 1: Show report with won/lose tickets only)

	exec LA_Rpt_SabaPromotion_UAT3 @BaseCurrencyName='EUR',@PartyIds='14',@FromDate='2019-12-01 00:00:00',@IsShowWonLose=0,@ToDate='2019-12-17 00:00:00'
 */
BEGIN
	SET NOCOUNT ON
	
	CREATE TABLE #PartyList (PartyId INT, PartyName VARCHAR(100), BranchName VARCHAR(100), ParentId	INT)
	INSERT INTO #PartyList EXEC bodb_licensee.dbo.LA_PartyListSel
	
	-- Region: Get Site Id
	DECLARE @SiteIds AS TABLE (
		PartyId		INT,
		LicenseeId	INT,
		FromDate	DATETIME,
		ToDate		DATETIME,
		IsDeposit	BIT)	

	INSERT INTO @SiteIds(PartyId, LicenseeId, FromDate, ToDate, IsDeposit)
	(
		SELECT DISTINCT c.PartyID, c.LicenseeID, @FromDate, @ToDate, c.isDeposit
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'SB', 'OA', 1) c		
	)
	-- End region

	-- ** Get Exchange 
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)
	
	-- Get current year
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	UPDATE #Exchange SET CurrencyCode = 'INH' WHERE ExchangeID = 51
	-- ** End Region
	
	-- ** Offer Currency
	DECLARE @OfferedCurrency AS TABLE (CurrencyId INT)
	INSERT INTO @OfferedCurrency (CurrencyId)
	SELECT e.ExchangeID FROM #Exchange e WHERE e.CurrencyCode IN ('CNY', 'THB', 'IDR', 'INH', 'MYR')
	
	-- ** Region: TempData
	CREATE TABLE #TempData (
		PartyID					INT,
		PartyName				NVARCHAR(100),
		WinLossDate				DATETIME,
		NumberOfCoupon			INT,
		NumberOfRedemption		INT,
		NonPeakHourTrans		INT,
		PromoDayTrans			INT,
		PromoDayTurnover		MONEY,
		PromoDayTurnoverOrigin	MONEY,
		PrizeRedeemed			MONEY,
		PrizeRedeemedOrigin		MONEY,
		CurrencyCode			VARCHAR(3))

	-- Calculate for desposit
	INSERT INTO #TempData (PartyID,PartyName,WinLossDate,NumberOfCoupon,NumberOfRedemption,NonPeakHourTrans,PromoDayTrans,PromoDayTurnover,PrizeRedeemed,PromoDayTurnoverOrigin,
						   PrizeRedeemedOrigin,CurrencyCode)	
	SELECT si.PartyId
		   ,p.PartyName
		   ,nph.RptDateGMT AS WinLossDate
		   ,SUM (nph.CouponCount) AS NumberOfCoupon
		   ,SUM (nph.RedemptionCount) AS NumberOfRedemption
		   ,CASE WHEN @IsShowWonLose = 0 THEN SUM(nph.BetCountOfPromoTime) ELSE SUM(nph.BetCountOfPromoTime_WonLose) END AS NonPeakHourTrans
		   ,CASE WHEN @IsShowWonLose = 0 THEN SUM(nph.BetCount) ELSE SUM(nph.BetCount_WonLose) END AS PromoDayTrans
		   -- Select origin 
		   ,CASE WHEN @IsShowWonLose = 0 THEN SUM(nph.Turnover * e.Rate) ELSE SUM(nph.Turnover_WonLose * e.Rate) END AS PromoDayTurnover
		   ,SUM(nph.RedemptionPrize * e.Rate) AS PrizeRedeemed 
		   -- Select by base currency
		   ,CASE WHEN @IsShowWonLose = 0 THEN SUM(nph.Turnover) ELSE SUM(nph.Turnover_WonLose) END AS PromoDayTurnoverOrigin
		   ,SUM(nph.RedemptionPrize) AS PrizeRedeemedOrigin
		   ,e.CurrencyCode 
	FROM bodb_LicenseeReport.dbo.rptLicPromotion nph WITH (NOLOCK)
		INNER JOIN @SiteIds si ON nph.SiteID = si.LicenseeId
		INNER JOIN #PartyList p ON si.PartyId = p.PartyId
		INNER JOIN #Exchange e ON e.ExchangeID = nph.CurrencyID
	WHERE nph.RptDateGMT BETWEEN si.FromDate AND si.ToDate 
		AND nph.CurrencyId <> 20
		AND si.isDeposit = 1
		AND nph.TimeZone = 8
		AND nph.CurrencyID IN (SELECT CurrencyID FROM @OfferedCurrency)
	GROUP BY nph.RptDateGMT, si.PartyId, p.PartyName, e.CurrencyCode
	-- ** End region
	
	SELECT * FROM #TempData
	
	DROP TABLE	#PartyList
	DROP TABLE	#Exchange
	DROP TABLE  #TempData	
END
GO