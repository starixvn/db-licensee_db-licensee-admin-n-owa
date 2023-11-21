/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].LA_GEN_LicPerformanceAnalysis_Report
	@FromDate		DATE,
	@ToDate			DATE,
	@ProductCodes	VARCHAR(MAX) = '',
	@Environment	VARCHAR(10),
	@IsOverwrite	BIT = 0,
	@PartyIds		VARCHAR(MAX) = ''
AS

/*
	Created: BRUCE
	Date: 20190312
	Task: Licensee Performance Analysis (PowerBI)
	DB: bodb_licensee
	Remark: generate licensee performance analysis report

	Revisions:
		- 20190312@Bruce: create SP [RedmineID: #105205]
		- 20200821@Parsons: Add one more column into result set [#139055]
		- 20210323@Parsons: Change BaseCurrency Of Licensee [#FeatureID 151466]
	    - 20210408@Parsons: Remove redundant linked server [#FeatureID 152089]
		- 20210909@Percy: Support Prorate min fee of Group Min Fee: apply core SP [RedmineID: #157652]
		- 20211209@Percy: Fix Base Currency IS NULL [RedmineID: #157652]
		- 20211213@Percy: Fix missing BetCount and exclude Saba Promotion [RedmineID: #161378]
		- 20211215@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20201003@Danny: Exclude Licensees that offer cryptocurrency [#FeatureID 177718]
		- 20230111@Danny: Discount group - Support many sportsbook charge rates [RedmineID: #169160]
		- 20230619@Danny: Get data Promotion And Sponsorship (ProductID = 37) [RedmineID: #189659]
		- 20230815@Danny: Handle crypto licensee billing with fiat currency [RedmineID: #192378]
		- 20231005@Danny: Change charge rate and tier rebate for Alek group from Oct 2023 [RedmineID: #194561]
		- 20231115@Danny: Final licensing fee for 3rd products [RedmineID: #191813]

*/

BEGIN
	SET NOCOUNT ON

	-- Get Product List
	DECLARE @tmpProductList TABLE (GroupProductId INT, ProductId INT, ProductCode VARCHAR(50), FromDate DATETIME, ToDate DATETIME)
	INSERT INTO @tmpProductList (GroupProductId, ProductId, ProductCode, FromDate, ToDate)
	SELECT GroupProductId, ProductId, ProductCode, FromDate, ToDate
	FROM dbo.LA_f_GroupProduct('', @FromDate, @ToDate) g   -- get all products

	DECLARE @tmpPartyOfferCrypto TABLE (PartyId INT)
	INSERT INTO @tmpPartyOfferCrypto(PartyId)
	SELECT  PartyID FROM LA_f_CryptoPartyListSel() WHERE IsBillingCryptoCurrency = 1

	IF ',' + @ProductCodes + ',' LIKE ',ADJUST,' -- Adjustment
		INSERT INTO @tmpProductList (ProductId, ProductCode)
		SELECT 9000, 'ADJUST'

	SELECT  @ProductCodes = STRING_AGG(ProductCode,',')
	FROM @tmpProductList g
	WHERE GroupProductId = ProductId 

	-- Get Party List
	DECLARE @tmpPartyList TABLE (PartyId INT, SiteId INT, BaseCurrencyId INT)

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


	DECLARE @PartyIds_AlekGroup VARCHAR(200), @isRecalRebate BIT = 0, @RecalRebateEffectiveFrom DATETIME , @RecalRebateEffectiveTo DATETIME

	SELECT @PartyIds_AlekGroup = STRING_AGG(CONVERT(VARCHAR(50), op.PartyID), ',')
	FROM bodb_licensee.dbo.OAS_Party op WITH(NOLOCK)
	INNER JOIN (
		SELECT CAST(value AS INT ) AS PartyID FROM STRING_SPLIT(@PartyIds, ',')
	) x ON op.PartyID = x.PartyID
	WHERE op.PartyName IN ('BigGaming','HuangMa','BGCV','VNS888')

	IF @PartyIds_AlekGroup IS NOT NULL
		SELECT @isRecalRebate = 1

	IF @isRecalRebate = 1
		SELECT @RecalRebateEffectiveFrom = '2023-10-01', @RecalRebateEffectiveTo = '2024-09-01'

	-- Generate adjustment values
	DECLARE @ReportDate DATE = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate), 0)
	IF EXISTS (SELECT 1 FROM @tmpProductList WHERE ProductId = 9000)
		EXEC dbo.LA_GEN_LicPerformanceAnalysis_Adjustment 
			@PartyIds = @PartyIDs, 
			@ReportDate = @ReportDate,
			@Environment = @Environment,
			@IsOverwrite = @IsOverwrite

	-- Get TO/WL data
	BEGIN
		-- Get Base Currency List
		DECLARE @CurrencyId INT, @CurrencyName VARCHAR(10)
			
		DECLARE @tmpBaseCurrencyList TABLE (CurrencyId INT, Code VARCHAR(10))
		INSERT INTO @tmpBaseCurrencyList (CurrencyId, Code)
		EXEC dbo.LA_SelBaseCurrency

		DECLARE @tmpChargeInfo TABLE (PartyId INT, LicenseeId INT, ProductId INT, FromDate DATE, ToDate DATE)
		INSERT INTO @tmpChargeInfo (PartyId, LicenseeId, ProductId, FromDate, ToDate)
		SELECT DISTINCT PartyId, LicenseeId, ProductId, Fromdate, ToDate
		FROM dbo.LA_f_ChargeInfo (@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
		WHERE DI_Rate > 0 AND ChargeType = 1

		IF @IsOverwrite = 0
		BEGIN
			;WITH CTE_Data AS (
				SELECT SiteId, ProductId
				FROM bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis WITH (NOLOCK)
				WHERE ReportDate = @ReportDate AND ProductId <> 9000 AND IsBillingCurrency = 1
				GROUP BY SiteId, ProductId
			)
			DELETE c
			FROM @tmpChargeInfo c
				INNER JOIN CTE_Data d ON c.LicenseeId = d.SiteId AND c.ProductId = d.ProductId
		END

		DELETE @tmpPartyList WHERE PartyId NOT IN (SELECT c.PartyId FROM @tmpChargeInfo c)

		IF @@ROWCOUNT > 0
		BEGIN
			SET @PartyIds = NULL
			SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM @tmpPartyList
		END

		CREATE TABLE #tmpPerfData (rptDate DATETIME, PartyId INT, CurrencyId INT, ProductId INT, BetCount INT, Turnover MONEY, TurnoverNoDraw MONEY, Winloss MONEY)
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
		DECLARE @Result TABLE
		(
			PartyId INT, ProductId INT, ProductCode VARCHAR(10), LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
			,Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000), Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000)
			,Winloss MONEY, Turnover MONEY, TurnoverNoDraw MONEY, BetCount INT, BaseCurrencyId INT, ExtraInfo NVARCHAR(4000)
		)

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

			IF @isRecalRebate =1 AND @FromDate BETWEEN @RecalRebateEffectiveFrom AND @RecalRebateEffectiveTo AND EXISTS (SELECT TOP 1 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value = 'SB')
			BEGIN
				DECLARE @Result_OldSetting TABLE
				(
					PartyId INT, ProductId INT, LicensingFeeTypeId SMALLINT, GrossLicensingFee MONEY, LicensingFee MONEY, ExtraAmount MONEY, IsChargedByGroupMinFee BIT, IsChargedByMinFee BIT
					,Rebate MONEY, RebateRate MONEY, RebateRemark NVARCHAR(4000), Discount MONEY, DiscountRate MONEY, DiscountRemark NVARCHAR(4000)
					,BetCount INT, Turnover MONEY, MemberWL MONEY, BACommission MONEY, IsPrevious BIT, ExtraInfo NVARCHAR(4000)
				)
				INSERT INTO @Result_OldSetting
				(
					PartyId, ProductId, LicensingFeeTypeId, GrossLicensingFee, LicensingFee, ExtraAmount, IsChargedByGroupMinFee, IsChargedByMinFee
					,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark, ExtraInfo
				)
				EXEC bodb_Licensee.dbo.LA_AmountToCompanyByProduct
					@PartyIds = @PartyIds_AlekGroup
					,@ProductCodes = 'SB'
					,@FromDate = @FromDate
					,@ToDate = @ToDate
					,@BaseCurrencyName = @CurrencyName
					,@IsUsePreviousSetting = 1

				IF EXISTS (SELECT TOP 1 1 FROM @Result_OldSetting) 
				BEGIN
					UPDATE r
					SET r.Rebate = ri.Rebate
					FROM @Result r
					INNER JOIN @Result_OldSetting ri ON r.PartyId = ri.PartyId AND r.ProductId = ri.ProductId AND ri.LicensingFeeTypeId = 0
					WHERE r.LicensingFeeTypeId = 0 AND r.PartyId IN (SELECT CAST(value AS INT) FROM STRING_SPLIT(@PartyIds_AlekGroup,','))
					AND r.BaseCurrencyId IS NULL
				END

				DELETE FROM @Result_OldSetting

				
			END

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

		DROP TABLE #tmpPerfData
	END

	DELETE a WITH (ROWLOCK)
	FROM bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis a
		INNER JOIN @tmpPartyList p ON a.SiteId = p.SiteId
		INNER JOIN @Result r ON p.PartyId = r.PartyId AND a.ProductId = r.ProductId AND a.CurrencyId = r.BaseCurrencyId
	WHERE a.ReportDate = @ReportDate

	INSERT INTO bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis
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
END
GO