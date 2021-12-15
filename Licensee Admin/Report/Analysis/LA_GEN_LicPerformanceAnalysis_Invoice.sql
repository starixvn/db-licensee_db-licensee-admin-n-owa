/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_GEN_LicPerformanceAnalysis_Invoice]
	@InvoiceID		INT,
	@ProductCodes	VARCHAR(MAX),
	@Environment	VARCHAR(10)
AS

/*
	Created: BRUCE
	Date: 20190226
	Task: Licensee Performance Analysis (PowerBI)
	DB: bodb_licensee
	Remark: generate licensee performance analysis report

	Revisions:
		- 20190226@Bruce: create SP [RedmineID: #105205]
		- 20200821@Parsons: Add one more column into result set [#139055]
		- 20210909@Percy: Support Prorate min fee of Group Min Fee: apply core SP [RedmineID: #157652]
		- 20211209@Percy: Fix Base Currency IS NULL [RedmineID: #157652]
		- 20211213@Percy: Fix missing BetCount and exclude Saba Promotion [RedmineID: #161378]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @PartyId INT, @SiteId INT, @InvoiceStatus SMALLINT, @InvoiceDate DATE
	DECLARE @AdjustmentId INT = 9000
	DECLARE @BaseCurrencyId INT = 6 -- default
	DECLARE @InvoiceStatus_Normal SMALLINT = 0

	SELECT
		@PartyId			= PartyId
		,@InvoiceStatus		= StatusId
		,@InvoiceDate		= DATEADD(MONTH, DATEDIFF(MONTH, 0, InvoiceDate), 0)
		,@BaseCurrencyId	= CurrencyId
	FROM dbo.LA_InvoiceHeader WITH (NOLOCK)
	WHERE InvoiceHeaderId = @InvoiceId AND Environment = @Environment

	IF @PartyId IS NULL
		RETURN

	SELECT @SiteId = OldRefId FROM dbo.OAS_Party WITH (NOLOCK) WHERE PartyId = @PartyId

	-- Get Product List
	DECLARE @tmpProductList TABLE (GroupProductId INT, ProductId INT, ProductCode VARCHAR(50))
	INSERT INTO @tmpProductList (GroupProductId, ProductId, ProductCode)
	SELECT ISNULL(g.GroupProductId, p.ProductId), ISNULL(g.ProductId, p.ProductId), ISNULL(g.ProductCode, p.ProductPrefix)
	FROM dbo.LA_f_Products3rd(@ProductCodes) p
		LEFT JOIN dbo.LA_f_GroupProduct() g ON p.ProductId = g.GroupProductId

	IF ',' + @ProductCodes + ',' LIKE ',ADJUST,' -- Adjustment
		INSERT INTO @tmpProductList (ProductId, ProductCode)
		SELECT 9000, 'ADJUST'

	-- Get Invoice
	DECLARE @StatementItemList TABLE (InvItemTypeId SMALLINT, ProductId INT)
	INSERT INTO @StatementItemList (InvItemTypeId, ProductId)
	SELECT s.InvItemTypeId, s.ProductId
	FROM dbo.LA_InvoiceHeader h WITH (NOLOCK)
		INNER JOIN dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId = s.InvoiceHeaderId
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

		DELETE bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis WITH (ROWLOCK)
		WHERE SiteId = @SiteId 
			AND ReportDate = @InvoiceDate 
			AND ProductId IN (SELECT s.ProductId FROM @StatementItemList s WHERE s.InvItemTypeId = 1)
			AND ProductId <> 9000 -- Adjustment

		IF @InvoiceStatus = 0 -- Normal
		BEGIN
			-- Get Base Currency List
			DECLARE @CurrencyId INT, @CurrencyName VARCHAR(10)
			
			DECLARE @tmpBaseCurrencyList TABLE (CurrencyId INT, Code VARCHAR(10))
			INSERT INTO @tmpBaseCurrencyList (CurrencyId, Code)
			EXEC dbo.LA_SelBaseCurrency

			-- Get TO/WL data
			DECLARE @PartyIds VARCHAR(MAX) = CONVERT(VARCHAR(MAX), @PartyId)
			DECLARE @FromDate DATETIME = @InvoiceDate
			DECLARE @ToDate DATETIME = DATEADD(DAY, -1, DATEADD(MONTH, DATEDIFF(MONTH, 0, @InvoiceDate) + 1, 0))

			DECLARE @tmpChargeInfo TABLE (ProductId INT, FromDate DATE, ToDate DATE)
			INSERT INTO @tmpChargeInfo (ProductId, FromDate, ToDate)
			SELECT DISTINCT ProductId, Fromdate, ToDate
			FROM dbo.LA_f_ChargeInfo (@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
			WHERE DI_Rate > 0

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
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
				INNER JOIN @tmpProductList p ON r.ProductId = p.ProductId
				INNER JOIN @tmpChargeInfo c ON p.GroupProductId = c.ProductId AND r.rptDate BETWEEN c.FromDate AND c.ToDate
				LEFT JOIN bodb_Licensee.dbo.LA_f_GroupBettype() gb ON r.Bettype = gb.Bettype
			WHERE r.rptDate BETWEEN @FromDate AND @ToDate
				AND r.SiteId = @SiteId
				AND r.CurrencyId <> 20
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
				,Winloss MONEY, Turnover MONEY, TurnoverNoDraw MONEY, BetCount INT, BaseCurrencyId INT
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
					,Discount, DiscountRate, DiscountRemark, Rebate, RebateRate, RebateRemark
				)
				EXEC dbo.LA_AmountToCompanyByProduct
					@PartyIds = @PartyIds
					,@ProductCodes = @ProductCodes
					,@FromDate = @FromDate
					,@ToDate = @ToDate
					,@BaseCurrencyName = @CurrencyName

				DELETE @Result WHERE ProductId = 37 -- Saba Promotion

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

			INSERT INTO bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis
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
				,LicensingFee + ExtraAmount	AS LicensingFee
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