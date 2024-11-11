/*<info serverAlias="DBLIC-bodb_licenseeReport" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licenseeReport
GO

ALTER PROCEDURE [dbo].[LA_GEN_LicPerformanceAnalysis_Invoice]
	@InvoiceID		INT,
	@ProductCodes	VARCHAR(MAX) = '',
	@Environment	VARCHAR(10)
AS

/*
	Created: BRUCE
	Date: 20190226
	Task: Licensee Performance Analysis (PowerBI)
	DB: bodb_licenseeReport
	Remark: generate licensee performance analysis report

	Revisions:
		- 20190226@Bruce: create SP [RedmineID: #105205]
		- 20200821@Parsons: Add one more column into result set [#139055]
		- 20210909@Percy: Support Prorate min fee of Group Min Fee: apply core SP [RedmineID: #157652]
		- 20211209@Percy: Fix Base Currency IS NULL [RedmineID: #157652]
		- 20211213@Percy: Fix missing BetCount and exclude Saba Promotion [RedmineID: #161378]
		- 20211215@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20220928@Danny: Exclude Licensees that offer cryptocurrency [#FeatureID 177627]
		- 20230111@Danny: Discount group - Support many sportsbook charge rates [RedmineID: #169160]
		- 20230619@Danny: Get data Promotion And Sponsorship (ProductID = 37) [RedmineID: #189659]
		- 20230815@Danny: Handle crypto licensee billing with fiat currency [RedmineID: #192378]
		- 20231005@Danny: Change charge rate and tier rebate for Alek group from Oct 2023 [RedmineID: #194561]
		- 20231115@Danny: Final licensing fee for 3rd products [RedmineID: #191813]
		- 20240109@Danny: Enhance rule regen data when invoice is voided [RedmineID: #199448]
		- 20240401@Danny: Change meta data [#203267]
		- 20240520@Danny: support closed status invoice [RedmineID: #194603]
		- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
		- 20241008@Sally: Support Odds Boost Voucher [#209884]

*/

BEGIN
	SET NOCOUNT ON

	DECLARE @PartyId INT, @SiteId INT, @InvoiceStatus SMALLINT, @InvoiceDate DATE
	DECLARE @AdjustmentId	INT = 9000
		,@OddsBoostBonusId  INT = 9002  
	DECLARE @BaseCurrencyId INT = 6 -- default

	DECLARE @tmpPartyOfferCrypto TABLE (PartyId INT)
	INSERT INTO @tmpPartyOfferCrypto(PartyId)
	SELECT  PartyID FROM bodb_licensee.dbo.LA_f_CryptoPartyListSel() WHERE IsBillingCryptoCurrency = 1

	SELECT
		@PartyId			= PartyId
		,@InvoiceStatus		= StatusId
		,@InvoiceDate		= DATEADD(MONTH, DATEDIFF(MONTH, 0, InvoiceDate), 0)
		,@BaseCurrencyId	= CurrencyId
	FROM bodb_licensee.dbo.LA_InvoiceHeader WITH (NOLOCK)
	WHERE InvoiceHeaderId = @InvoiceId AND Environment = @Environment

	DECLARE @FromDate DATETIME = @InvoiceDate
	DECLARE @ToDate DATETIME = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, 0, @InvoiceDate) + 1, 0))

	IF (@PartyId IS NULL OR EXISTS (SELECT TOP 1 1 FROM @tmpPartyOfferCrypto WHERE PartyId = @PartyId))
		RETURN

	SELECT @SiteId = OldRefId FROM bodb_licensee.dbo.OAS_Party WITH (NOLOCK) WHERE PartyId = @PartyId
	-- Get Product List
	DECLARE @tmpProductList TABLE (GroupProductId INT, ProductId INT, ProductCode VARCHAR(50), FromDate DATETIME, ToDate DATETIME)
	INSERT INTO @tmpProductList (GroupProductId, ProductId, ProductCode, FromDate, ToDate)
	SELECT	GroupProductId, ProductId, ProductCode, FromDate, ToDate
	FROM	bodb_licensee.dbo.LA_f_GroupProduct('', @FromDate, @ToDate) g  -- Get all products

	IF ',' + @ProductCodes + ',' LIKE ',ADJUST,' -- Adjustment
		INSERT INTO @tmpProductList (ProductId, ProductCode)
		SELECT 9000, 'ADJUST'

	SELECT  @ProductCodes = STRING_AGG(ProductCode,',')
	FROM @tmpProductList g
	WHERE GroupProductId = ProductId 
	
	SELECT @ProductCodes = @ProductCodes + ',SPR(CS)'

	-- Get Invoice
	DECLARE @StatementItemList TABLE (InvItemTypeId SMALLINT, ProductId INT)
	INSERT INTO @StatementItemList (InvItemTypeId, ProductId)
	SELECT s.InvItemTypeId, s.ProductId
	FROM bodb_licensee.dbo.LA_InvoiceHeader h WITH (NOLOCK)
		INNER JOIN bodb_licensee.dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId = s.InvoiceHeaderId
		LEFT JOIN @tmpProductList p ON s.ProductId = p.ProductId AND s.InvItemTypeId = 1
	WHERE h.InvoiceHeaderId = @InvoiceId
		AND s.InvItemTypeId IN (1, 10, 11, 12, 13, 14, 17, 20)
		AND (s.InvItemTypeId <> 1 OR p.ProductId IS NOT NULL)

	IF EXISTS (SELECT 1 FROM @StatementItemList WHERE InvItemTypeId = 1) -- Software Fee
	BEGIN
		SET @ProductCodes = NULL
		SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + p.ProductCode
		FROM @tmpProductList p
		WHERE p.ProductId IN (SELECT s.ProductId FROM @StatementItemList s WHERE s.InvItemTypeId = 1)

		SELECT @ProductCodes = @ProductCodes + ',SPR(CS)'
		WHERE EXISTS (SELECT TOP 1 1 FROM STRING_SPLIT(@ProductCodes,',') WHERE value <> 'SB')

		DELETE dbo.rptLicPerformanceAnalysis WITH (ROWLOCK)
		WHERE SiteId = @SiteId 
			AND ReportDate = @InvoiceDate 
			--AND ProductId IN (SELECT s.ProductId FROM @StatementItemList s WHERE s.InvItemTypeId = 1)
			AND ProductId <> 9000 -- Adjustment

		IF @InvoiceStatus <> -1
		BEGIN
			-- Get Base Currency List
			DECLARE @CurrencyId INT, @CurrencyName VARCHAR(10)
			
			DECLARE @tmpBaseCurrencyList TABLE (CurrencyId INT, Code VARCHAR(10))
			INSERT INTO @tmpBaseCurrencyList (CurrencyId, Code)
			EXEC bodb_licensee.dbo.LA_SelBaseCurrency

			-- Get TO/WL data
			DECLARE @PartyIds VARCHAR(MAX) = CONVERT(VARCHAR(MAX), @PartyId)
		
			DECLARE @tmpChargeInfo TABLE (ProductId INT, FromDate DATE, ToDate DATE)
			INSERT INTO @tmpChargeInfo (ProductId, FromDate, ToDate)
			SELECT DISTINCT ProductId, Fromdate, ToDate
			FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
			WHERE DI_Rate > 0 AND ChargeType = 1

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

			CREATE TABLE #tmpPerfData (rptDate DATETIME, CurrencyId INT, ProductId INT, BetCount INT, Turnover MONEY, TurnoverNoDraw MONEY, Winloss MONEY)
			INSERT INTO #tmpPerfData (rptDate, CurrencyId, ProductId, BetCount, Turnover, TurnoverNoDraw, Winloss)
			SELECT r.rptDate, r.CurrencyId, p.GroupProductId
				,SUM(r.BetCount) AS BetCount
				,SUM(r.Turnover) AS Turnover
				,SUM(r.Turnover * CASE
									WHEN StatusId = 111 THEN 0.0
									WHEN StatusId IN (114, 115) THEN 0.5
									ELSE 1.0 END
					) AS TurnoverNoDraw
				,SUM(-r.MemberWL - CASE WHEN r.ProductId = 31 THEN r.CommissionP ELSE 0 END) AS Winloss
			FROM dbo.rpt_BettingByProduct r WITH (NOLOCK)
				INNER JOIN @tmpProductList p ON r.ProductId = p.ProductId AND r.rptDate BETWEEN p.FromDate AND p.ToDate
				INNER JOIN @tmpChargeInfo c ON p.GroupProductId = c.ProductId AND r.rptDate BETWEEN c.FromDate AND c.ToDate
				LEFT JOIN bodb_Licensee.dbo.LA_f_GroupBettype() gb ON r.Bettype = gb.Bettype
			WHERE r.rptDate BETWEEN @FromDate AND @ToDate
				AND r.SiteId = @SiteId
				AND r.CurrencyId NOT IN ( SELECT x.ExchangeID FROM bodb_licensee.dbo.LA_f_ExcludedCurrencyListSel() x)
				AND r.CustomerCategory NOT IN (27, 28)
				AND r.Bettype NOT IN (901, 902, 903, 904, 911, 912, 913, 914)
				AND r.StatusId IN (111, 112, 113, 114, 115)
				AND gb.Bettype IS NULL
				AND ISNULL(r.TicketType, 0) <> 2
			GROUP BY r.rptDate, r.CurrencyId, p.GroupProductId

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
				EXEC bodb_Licensee.dbo.LA_AmountToCompanyByProduct
					@PartyIds = @PartyIds
					,@ProductCodes = @ProductCodes
					,@FromDate = @FromDate
					,@ToDate = @ToDate
					,@BaseCurrencyName = @CurrencyName
					,@LicensingFeeTypeIds = '0,13,14'-- 13 = Casino promotion, 14: Odds Boost Adjustment								

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
						SELECT t.ProductId
							,SUM(t.BetCount) AS BetCount
							,SUM(t.Winloss * e.BaseCurrencyRate) AS Winloss
							,SUM(t.Turnover * e.BaseCurrencyRate) AS Turnover
							,SUM(t.TurnoverNoDraw * e.BaseCurrencyRate) AS TurnoverNoDraw
						FROM #tmpPerfData t
							INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CurrencyName) e ON t.CurrencyId = e.ExchangeId AND t.rptDate = e.ExchangeDate
						GROUP BY t.ProductId
					) t ON r.ProductId = t.ProductId
				WHERE r.BaseCurrencyId IS NULL
			END

				-- Insert data Odds Boost Bonus 
			IF EXISTS (SELECT TOP 1 1 FROM @Result WHERE LicensingFeeTypeId = 14)
			BEGIN
				INSERT INTO dbo.rptLicPerformanceAnalysis(
					ReportDate, SiteId, ProductId, CurrencyId, IsBillingCurrency
					,BetCount, Turnover, TurnoverNoDraw, LicenseeWinloss, LicensingFee, Discount, Rebate, Adjustment
				)
				SELECT @InvoiceDate
					,@SiteId
					,@OddsBoostBonusId AS ProductId
					,r.BaseCurrencyId
					,CASE WHEN BaseCurrencyId = @BaseCurrencyId THEN 1 ELSE 0 END AS IsBillingCurrency
					,0 AS BetCount
					,0 AS Turnover
					,0 AS TurnoverNoDraw
					,0 AS LicenseeWinloss
					,r.ExtraAmount AS LicensingFee
					,0 AS Discount
					,0 AS Rebate
					,0 AS Adjustment
				FROM @Result r
				WHERE r.ProductId = 0
					AND r.LicensingFeeTypeId = 14

				DELETE FROM @Result WHERE LicensingFeeTypeId = 14
			END

			INSERT INTO dbo.rptLicPerformanceAnalysis
			(
				ReportDate, SiteId, ProductId, CurrencyId, IsBillingCurrency
				,BetCount, Turnover, TurnoverNoDraw, LicenseeWinloss, LicensingFee, Discount, Rebate, Adjustment
			)
			SELECT
				@InvoiceDate, @SiteId, ProductId, BaseCurrencyId
				,CASE WHEN BaseCurrencyId = @BaseCurrencyId THEN 1 ELSE 0 END AS IsBillingCurrency
				,ISNULL(BetCount, 0)		AS BetCount
				,ISNULL(Turnover, 0)		AS Turnover
				,ISNULL(TurnoverNoDraw, 0)	AS TurnoverNoDraw
				,ISNULL(Winloss, 0)			AS LicenseeWinloss
				,CASE WHEN ProductId IN (-37, 74 ) THEN ExtraAmount ELSE LicensingFee + ExtraAmount END AS LicensingFee
				,Discount
				,Rebate
				,0 AS Adjustment
			FROM @Result

			DROP TABLE #tmpPerfData
		END

		-- Adjustment
		IF EXISTS (SELECT TOP 1 1 FROM @StatementItemList WHERE InvItemTypeId <> 1)
			AND EXISTS (SELECT TOP 1 1 FROM @tmpProductList WHERE ProductId = @AdjustmentId)
		BEGIN
			EXEC dbo.LA_GEN_LicPerformanceAnalysis_Adjustment 
				@PartyIds = @PartyId, 
				@ReportDate = @InvoiceDate, 
				@Environment = @Environment,
				@IsOverwrite = 1
		END
	END
END
GO