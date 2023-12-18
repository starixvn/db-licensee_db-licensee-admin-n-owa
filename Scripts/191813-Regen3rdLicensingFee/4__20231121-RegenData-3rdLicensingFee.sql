/*<info serverAlias="DBLIC-bodb_licensee"></info>*/
/*
	Created: 20231121@Danny
	DB: DBLIC-bodb_Licensee
	Task: Insert Data 3rd products [#191813]
	-- Run DB053 only
*/
USE bodb_Licensee
GO

SET NOCOUNT ON 

DECLARE 
	@FromDate		DATE = '2023-07-01'

DECLARE
	@ToDate			DATE =  EOMONTH(@FromDate),
	@ProductCodes	VARCHAR(MAX) = 'SB',
	@PartyIds		VARCHAR(MAX) = ''

DECLARE @tmpProductList TABLE (GroupProductId INT, ProductId INT, ProductCode VARCHAR(50), FromDate DATETIME, ToDate DATETIME)
DECLARE @ReportDate DATE
DECLARE @tmpPartyOfferCrypto TABLE (PartyId INT)
INSERT INTO @tmpPartyOfferCrypto(PartyId)
SELECT  PartyID FROM LA_f_CryptoPartyListSel() WHERE IsBillingCryptoCurrency = 1

DECLARE @tmpPartyList TABLE (PartyId INT, SiteId INT, BaseCurrencyId INT)

DECLARE @tmpBaseCurrencyList TABLE (CurrencyId INT, Code VARCHAR(10))
INSERT INTO @tmpBaseCurrencyList (CurrencyId, Code)
EXEC dbo.LA_SelBaseCurrency

DECLARE @CurrencyId INT, @CurrencyName VARCHAR(10)
DECLARE @tmpChargeInfo TABLE (PartyId INT, LicenseeId INT, ProductId INT, FromDate DATE, ToDate DATE)

CREATE TABLE #tmpPerfData (rptDate DATETIME, PartyId INT, CurrencyId INT, ProductId INT, BetCount INT, Turnover MONEY, TurnoverNoDraw MONEY, Winloss MONEY)

DECLARE @Result TABLE
(
	PartyId INT, ProductId INT, ProductCode VARCHAR(10), LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
	,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000)
	,Winloss MONEY, Turnover MONEY, TurnoverNoDraw MONEY, BetCount INT, BaseCurrencyId INT, ExtraInfo NVARCHAR(4000)
)

WHILE @ToDate <= '2023-08-31'
BEGIN
	--select @FromDate, @ToDate
	-- Get Product List
	DELETE FROM @tmpProductList
	DELETE FROM @tmpPartyList
	DELETE FROM @tmpChargeInfo
	TRUNCATE TABLE #tmpPerfData
	DELETE FROM @Result

	SELECT @ProductCodes = '', @PartyIds = ''
	
	INSERT INTO @tmpProductList (GroupProductId, ProductId, ProductCode, FromDate, ToDate)
	SELECT GroupProductId, ProductId, ProductCode, FromDate, ToDate
	FROM dbo.LA_f_GroupProduct(@ProductCodes, @FromDate, @ToDate) g

	SELECT  @ProductCodes = STRING_AGG(ProductCode,',')
	FROM dbo.LA_f_GroupProduct('SB', @FromDate, @ToDate) g
	WHERE GroupProductId = ProductId --AND ProductCode <> 'SB' 

	-- Get Party List
	IF ISNULL(@PartyIds, '') <> ''
	BEGIN
		INSERT INTO @tmpPartyList (PartyId)
		SELECT DISTINCT value FROM STRING_SPLIT(@PartyIds, ',')

		UPDATE t
		SET t.SiteId = p.OldRefId, t.BaseCurrencyId = ISNULL(c.BaseCurrencyId, 6)
		FROM @tmpPartyList t
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON t.PartyId = p.PartyId AND p.PartyType = 1
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyId = pd.PartyId AND pd.IsDeposit = 1
			OUTER APPLY (
				SELECT TOP 1 bc.BaseCurrencyId
				FROM dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK)
				WHERE p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
				ORDER BY bc.ToDate DESC
			) c

		DELETE @tmpPartyList WHERE SiteId IS NULL
	END
	ELSE
	BEGIN
		INSERT INTO @tmpPartyList (PartyId, SiteId, BaseCurrencyId)
		SELECT p.PartyId, p.OldRefId, ISNULL(c.BaseCurrencyId, 6)
		FROM dbo.OAS_Party p WITH (NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyId = pd.PartyId AND pd.IsDeposit = 1
			OUTER APPLY (
				SELECT TOP 1 bc.BaseCurrencyId
				FROM dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK)
				WHERE p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
				ORDER BY bc.ToDate DESC
			) c
		WHERE p.PartyType = 1 AND p.OldRefId IS NOT NULL
	END

	SET @PartyIds = NULL
	SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(20), t.PartyId) FROM @tmpPartyList t
	WHERE t.PartyId NOT IN (SELECT x.PartyId FROM @tmpPartyOfferCrypto x)

	-- Generate adjustment values
	SELECT @ReportDate = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate), 0)

	print 'running -----: ' + CAST (@ReportDate AS VARCHAR(50))
	
	-- Get TO/WL data
	BEGIN
		INSERT INTO @tmpBaseCurrencyList (CurrencyId, Code)
		EXEC dbo.LA_SelBaseCurrency
		
		-- Get Base Currency List
		INSERT INTO @tmpChargeInfo (PartyId, LicenseeId, ProductId, FromDate, ToDate)
		SELECT DISTINCT PartyId, LicenseeId, ProductId, Fromdate, ToDate
		FROM dbo.LA_f_ChargeInfo (@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
		WHERE DI_Rate > 0 AND ChargeType = 1 --AND (LicenseeId < 1000 OR LicenseeId >= 50000)

		DELETE @tmpPartyList WHERE PartyId NOT IN (SELECT c.PartyId FROM @tmpChargeInfo c)

		IF @@ROWCOUNT > 0
		BEGIN
			SET @PartyIds = NULL
			SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM @tmpPartyList
		END

		INSERT INTO #tmpPerfData (rptDate, PartyId, CurrencyId, ProductId, BetCount, Turnover, TurnoverNoDraw, Winloss)
		SELECT r.rptDate, c.PartyId, r.CurrencyId, p.GroupProductId
			,SUM(r.BetCount) AS BetCount
			,SUM(r.Turnover) AS Turnover
			,SUM(r.Turnover * CASE
								WHEN StatusId = 111 THEN 0.0
								WHEN StatusId IN (114, 115) THEN 0.5
								ELSE 1.0 END
				) AS TurnoverNoDraw
			,SUM(-r.MemberWL - CASE WHEN r.ProductId = 31 THEN r.CommissionP ELSE 0 END) AS Winloss
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
			INNER JOIN @tmpProductList p ON r.ProductId = p.ProductId AND r.rptDate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN @tmpChargeInfo c ON r.SiteId = c.LicenseeId AND p.GroupProductId = c.ProductId AND r.rptDate BETWEEN c.FromDate AND c.ToDate
			LEFT JOIN bodb_Licensee.dbo.LA_f_GroupBettype() gb ON r.Bettype = gb.Bettype
		WHERE r.rptDate BETWEEN @FromDate AND @ToDate
			AND r.CurrencyId <> 20
			AND r.CustomerCategory NOT IN (27, 28)
			AND r.Bettype NOT IN (901, 902, 903, 904, 911, 912, 913, 914)
			AND r.StatusId IN (111, 112, 113, 114, 115)
			AND gb.Bettype IS NULL
			AND ISNULL(r.TicketType, 0) <> 2
		GROUP BY r.rptDate, c.PartyId, r.CurrencyId, p.GroupProductId

		-- Get Licensing Fee
		WHILE 1 = 1
		BEGIN
			SELECT TOP 1 @CurrencyId = CurrencyId, @CurrencyName = Code FROM @tmpBaseCurrencyList
			DELETE @tmpBaseCurrencyList WHERE CurrencyId = @CurrencyId

			IF @@ROWCOUNT = 0
				BREAK

			INSERT INTO @Result
			(
				PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
				,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
			)
			EXEC dbo.LA_AmountToCompanyByProduct
				@PartyIds = @PartyIds
				,@ProductCodes = @ProductCodes
				,@FromDate = @FromDate
				,@ToDate = @ToDate
				,@BaseCurrencyName = @CurrencyName

			delete from @Result where ProductId <> 37
			UPDATE r
			SET r.BetCount = t.BetCount
				,r.Winloss = t.Winloss
				,r.Turnover = t.Turnover
				,r.TurnoverNoDraw = t.TurnoverNoDraw
				,r.BaseCurrencyId = @CurrencyId
			FROM @Result r
				LEFT JOIN (
					SELECT t.PartyId, t.ProductId
						,SUM(t.BetCount) AS BetCount
						,SUM(t.Winloss * e.BaseCurrencyRate) AS Winloss
						,SUM(t.Turnover * e.BaseCurrencyRate) AS Turnover
						,SUM(t.TurnoverNoDraw * e.BaseCurrencyRate) AS TurnoverNoDraw
					FROM #tmpPerfData t
						INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CurrencyName) e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate
					GROUP BY t.PartyId, t.ProductId
				) t ON r.PartyId = t.PartyId AND r.ProductId = t.ProductId
			WHERE r.BaseCurrencyId IS NULL
		END

	
	END

	INSERT INTO bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis_regen_UAT
	(
		ReportDate, SiteId, ProductId, CurrencyId, IsBillingCurrency
		,BetCount, Turnover, TurnoverNoDraw, LicenseeWinloss, LicensingFee, Discount, Rebate, Adjustment
	)
	SELECT @ReportDate, p.SiteId, r.ProductId, r.BaseCurrencyId
		,CASE WHEN r.BaseCurrencyId = p.BaseCurrencyId THEN 1 ELSE 0 END AS IsBillingCurrency
		,ISNULL(r.BetCount, 0)			AS BetCount
		,ISNULL(r.Turnover, 0)			AS Turnover
		,ISNULL(r.TurnoverNoDraw, 0)	AS TurnoverNoDraw
		,ISNULL(r.Winloss, 0)			AS LicenseeWinloss
		,CASE WHEN ProductId = 74 THEN r.ExtraAmount ELSE r.LicensingFee + r.ExtraAmount END AS LicensingFee
		,r.Discount
		,r.Rebate
		,0 AS Adjustment
	FROM @Result r
		INNER JOIN @tmpPartyList p ON r.PartyId = p.PartyId
	--WHERE r.BetCount <> 0

	SELECT @FromDate = DATEADD(MONTH,1,@FromDate)
	SELECT @ToDate	=  EOMONTH(@FromDate)

END

	DROP TABLE #tmpPerfData
GO


