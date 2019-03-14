/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].LA_GEN_LicPerformanceAnalysis_Invoice (
	@InvoiceID		INT,
	@ProductCodes	VARCHAR(500),
	@Environment	VARCHAR(10)
)
AS
/*
	Created: BRUCE
	Date: 20190226
	Task: Licensee Performance Analysis (PowerBI)
	DB: bodb_licensee
	Remark: generate licensee performance analysis report

	Revisions:
		- 20190226@Bruce: create SP [RedmineID: #105205]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @PartyId INT = NULL
	DECLARE @InvoiceStatus SMALLINT
	DECLARE @InvoiceDate DATE
	DECLARE @AdjustmentId INT = 9000
	DECLARE @BaseCurrency INT = 6
	DECLARE @InvoiceStatus_Normal	SMALLINT = 0

	SELECT @PartyId = PartyId, @InvoiceStatus = [StatusId], @InvoiceDate = DATEADD(MONTH, DATEDIFF(MONTH, 0, InvoiceDate), 0), @BaseCurrency = CurrencyId
	FROM dbo.LA_InvoiceHeader WITH(NOLOCK) WHERE InvoiceHeaderId = @InvoiceID AND Environment = @Environment

	-- stop generating, no invoice found
	IF @PartyId IS NULL RETURN;

	DECLARE @SiteId INT = (SELECT p.OldRefID FROM dbo.OAS_Party p WITH (NOLOCK) WHERE p.PartyID = @PartyId)

	-- Product list
	--
	DECLARE @tmpProductList TABLE (ProductId INT, ProductCode VARCHAR(20))
	INSERT INTO @tmpProductList(ProductId,ProductCode)
	SELECT p.ProductId, p.ProductCode
	FROM dbo.LA_f_LicPerformanceAnalysisProduct() p
	WHERE p.ProductCode IN (SELECT val FROM dbo.strSplit(@ProductCodes,','))

	-- invoice item types
	--
	DECLARE @InvItemType_SoftwareFee SMALLINT = 1
	DECLARE @SupportedInvoiceItemTypes TABLE(Id SMALLINT)
	INSERT INTO @SupportedInvoiceItemTypes(Id)
	SELECT val FROM dbo.strSplit('1,10,11,12,13,14,17,20',',')

	-- invoice status
	--
	DECLARE @StatementItemList TABLE(InvItemTypeId SMALLINT, ProductId INT)
	INSERT INTO @StatementItemList(InvItemTypeId,ProductId)
	SELECT s.InvItemTypeId, s.ProductId
	FROM dbo.LA_InvoiceHeader h WITH (NOLOCK)
	INNER JOIN dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId=s.InvoiceHeaderId
	INNER JOIN @SupportedInvoiceItemTypes r ON r.Id = s.InvItemTypeId
	WHERE h.InvoiceHeaderId = @InvoiceID

	-- remove unsupported products
	--
	DELETE @StatementItemList 
	WHERE InvItemTypeId = @InvItemType_SoftwareFee AND ProductId NOT IN (SELECT p.ProductId FROM @tmpProductList p)

	IF EXISTS (SELECT TOP 1 1 FROM @StatementItemList WHERE InvItemTypeId = @InvItemType_SoftwareFee)
	BEGIN
		-- only generate product in selected invoice
		--
		DELETE bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis
		WHERE SiteId = @SiteId 
			AND ReportDate = @InvoiceDate 
			AND ProductId IN (SELECT s.ProductId FROM @StatementItemList s WHERE s.InvItemTypeId = @InvItemType_SoftwareFee)
			AND ProductId <> @AdjustmentId

		SET @ProductCodes = (
			SELECT p.ProductCode +','
			FROM @tmpProductList p
			WHERE p.ProductId IN (SELECT s.ProductId FROM @StatementItemList s WHERE s.InvItemTypeId = @InvItemType_SoftwareFee)
			FOR XML PATH('')
		)

		SET @ProductCodes = LEFT(@ProductCodes, LEN(@ProductCodes) - 1)

		-- Normal voice
		--
		IF @InvoiceStatus = @InvoiceStatus_Normal
		BEGIN
			-- Base currency list
			--
			DECLARE @tmpBaseCurrencyList TABLE(CurrencyId INT, Code VARCHAR(10))
			INSERT INTO @tmpBaseCurrencyList(CurrencyId,Code)
			EXEC dbo.LA_SelBaseCurrency

			DECLARE @BaseCurrencyCode VARCHAR(10) = (SELECT Code FROM @tmpBaseCurrencyList WHERE CurrencyId = @BaseCurrency)

			-- Charge info
			--
			DECLARE @tmpChargeInfo TABLE(
				ProductId	INT,
				Rate		DECIMAL(6,5),
				FromDate	DATE,
				ToDate		DATE
			)

			DECLARE @FromDate DATE = @InvoiceDate
			DECLARE @ToDate DATE = DATEADD(day,-(DAY(DATEADD(month,1,@InvoiceDate))), DATEADD(month,1,@InvoiceDate))
			DECLARE @PartyIDs VARCHAR(10) = CAST(@PartyId AS VARCHAR(10))

			INSERT INTO @tmpChargeInfo(ProductId,Rate,FromDate,ToDate)
			SELECT DISTINCT ci.ProductID, ci.DI_Rate AS Rate, ci.Fromdate, ci.ToDate
			FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
			WHERE DI_Rate > 0 AND ProductID IN (SELECT s.ProductId FROM @StatementItemList s WHERE s.InvItemTypeId = @InvItemType_SoftwareFee)

			-- Turnover, Betcount, Turnover no draw
			--
			SELECT b.rptDate,b.CurrencyId, p.ProductId,
				SUM(-b.MemberWL) AS Winloss, -- not support GD tip yet
				SUM(b.BetCount) AS BetCount,
				SUM(b.Turnover) AS Turnover,
				SUM(b.Turnover * (CASE WHEN b.StatusId = 111 THEN 0 WHEN b.StatusId IN (114, 115) THEN 0.5 ELSE 1 END)) AS TurnoverNoDraw
			INTO #tmpPerfData
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN @tmpChargeInfo p ON b.ProductId = p.ProductID AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND @SiteId = b.SiteId
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914) -- exclude BT, CO
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
			GROUP BY b.rptDate,b.CurrencyId, p.ProductId

			-- Amount to company
			--
			DECLARE @tmpAmountToCompany TABLE(
				PartyId				INT,
				ProductId			INT,
				Fee					MONEY,
				Discount			MONEY,
				Rebate				MONEY,
				IsChargedByMinFee	BIT,
				Winloss				MONEY,
				Turnover			MONEY,
				TurnoverNoDraw		MONEY,
				BetCount			INT,
				CurrencyId			INT
			)

			DECLARE @tmpCurrency INT = 0
			DECLARE @tmpCurrencyCode VARCHAR(10)

			WHILE EXISTS (SELECT TOP 1 * FROM @tmpBaseCurrencyList)
			BEGIN
				SELECT TOP 1 @tmpCurrencyCode = Code, @tmpCurrency = CurrencyId FROM @tmpBaseCurrencyList
				DELETE @tmpBaseCurrencyList WHERE CurrencyId = @tmpCurrency

				INSERT INTO @tmpAmountToCompany(PartyId,ProductId,Fee,Discount,Rebate,IsChargedByMinFee)
				EXEC dbo.LA_AmountToCompanyByDiscountCurrencySel
					@FromDate = @FromDate,
					@ToDate = @ToDate,
					@PartyIDs = @PartyIDs,
					@ProductCodes = @ProductCodes,
					@BaseCurrencyName = @tmpCurrencyCode,
					@BaseCurrencyId = @tmpCurrency,
					@CurrencyId = 0

				;WITH cte_Data AS(
					SELECT b.ProductId,
						SUM(b.BetCount) AS BetCount,
						SUM(b.Winloss * e.BaseCurrencyRate) AS Winloss,
						SUM(b.Turnover * e.BaseCurrencyRate) AS Turnover,
						SUM(b.TurnoverNoDraw * e.BaseCurrencyRate) AS TurnoverNoDraw
					FROM #tmpPerfData b
					INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate,@ToDate, @tmpCurrencyCode) e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
					GROUP BY b.ProductId
				)
				UPDATE a SET
					Winloss = d.Winloss,
					Turnover = d.Turnover,
					TurnoverNoDraw = d.TurnoverNoDraw,
					BetCount = d.BetCount
				FROM @tmpAmountToCompany a
				INNER JOIN cte_Data d ON d.ProductID=a.ProductId
				WHERE a.CurrencyId IS NULL

				UPDATE @tmpAmountToCompany SET CurrencyId = @tmpCurrency WHERE CurrencyId IS NULL
			END

			INSERT INTO bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis(ReportDate,SiteId,ProductId,CurrencyId,IsBillingCurrency,BetCount,Turnover,TurnoverNoDraw,LicenseeWinloss,LicensingFee,Discount,Rebate,Adjustment)
			SELECT @InvoiceDate,@SiteId,a.ProductId,a.CurrencyId,
				CASE WHEN a.CurrencyId = @BaseCurrency THEN 1 ELSE 0 END AS IsBillingCurrency,
				ISNULL(a.BetCount,0)		AS BetCount,
				ISNULL(a.Turnover,0)		AS Turnover,
				ISNULL(a.TurnoverNoDraw,0)	AS TurnoverNoDraw,
				ISNULL(a.Winloss,0)			AS Winloss,
				a.Fee,
				a.Discount,
				a.Rebate,
				0
			FROM @tmpAmountToCompany a

			DROP TABLE #tmpPerfData
		END
	END

	-- mark adjustment values need to be regenerated
	--
	IF	EXISTS (SELECT TOP 1 1 FROM @StatementItemList WHERE InvItemTypeId <> @InvItemType_SoftwareFee) AND
		EXISTS (SELECT TOP 1 1 FROM @tmpProductList WHERE ProductId = @AdjustmentId)
	BEGIN
		EXEC dbo.LA_GEN_LicPerformanceAnalysis_Adjustment 
			@PartyIds = @PartyId, 
			@ReportDate = @InvoiceDate, 
			@Environment = @Environment,
			@IsOverwrite = 1
	END
END
GO 
