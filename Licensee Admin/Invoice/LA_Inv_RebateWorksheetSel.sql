/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE dbo.LA_Inv_RebateWorksheetSel
	@PartyId		INT
	, @FromDate		SMALLDATETIME
	, @ToDate		SMALLDATETIME
AS
/*	Created: 20170417@Bruce
	Task: Rebate worksheet [#76133]
	DB: bodb_licensee

	Revision:
	  - 20170710@bruce: include CO, CB, BA [#79741]
	  - 20171220@Parsons: increase length for variables [#88197]
	  - 20180126@Bruce: Exclude Exchange-BX [#87754]
	  - 20180419@Scofield: update CB for FreePlay [#93907]
	  - 20180716@bruce: add new group TEST for credit [#98126]
	  - 20180712@Bruce: Enhance Manage Discount group [#94282]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @BaseCurrency VARCHAR(10) = ISNULL((
			SELECT TOP 1 Code 
			FROM bodb02.dbo.Exchange e WITH(NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON e.exchangeid = d.BaseCurrencyId
			WHERE d.PartyID = @PartyId
		),6) -- default is EUR

	-- products
	DECLARE @Products TABLE (ProductId INT, ProductCode VARCHAR(20))
	INSERT INTO @Products
	SELECT DISTINCT p.ProductID, p.ProductPrefix
	FROM LA_f_Products3rd('') p
	INNER JOIN dbo.OAS_ChargeInfo c WITH(NOLOCK) ON c.ProductID = p.ProductID
	WHERE c.FromParty = @PartyId AND c.ProductId NOT IN (1,23,13,14,17,31 ) --exclude RB,bettrade,NG2, MGCLC,MGCRNG,BX

	-- Region: Party charge info
	DECLARE @CB INT = 15, @CO INT = 25, @BA INT = 3
	DECLARE @PartyIds VARCHAR(10) = CAST(@PartyId AS VARCHAR(10))
	DECLARE @ProductCodes VARCHAR(2000) = (SELECT ProductCode + ',' FROM @Products FOR XML PATH(''))
	DECLARE @PartyChargeInfo AS TABLE (
		PartyId		INT,
		LicenseeId	INT,
		ProductID	INT,
		Rate		DECIMAL(9,8),
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME,
		TypeId		SMALLINT
	)

	-- include CO, BA [#79741]
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
		WHERE	DI_Rate > 0 AND ProductID <> @CB -- exclude CB
	)

	-- include CB [#79741]
	DECLARE @CommChargeType INT = 6
	DECLARE @CashInShareChargeType INT = 7

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, TypeId, FromDate, ToDate)
	SELECT	ci.FromParty,
			p.OldRefID,
			@CB,
			ci.Rate,
			ci.ChargeType,
			CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
			CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
	FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
		LEFT JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
	WHERE EXISTS(SELECT TOP 1 1 FROM @Products WHERE ProductId=@CB)
		AND FromParty = @PartyId
		AND ProductID = @CB
		AND pd.IsDeposit = 1
		AND ChargeType IN (@CommChargeType,@CashInShareChargeType)
		AND @FromDate <= ci.ToDate
		AND ci.FromDate <= @ToDate
	-- End region

	-- keep active products
	DELETE @Products WHERE ProductId NOT IN (SELECT p.ProductId FROM @PartyChargeInfo p WHERE p.PartyId = @PartyId)

	-- get amount to company,discount,rebate(only for some supported products
	CREATE TABLE #AmountToCompany (
		PartyId			INT,
		ProductId		INT,
		Winloss			MONEY,
		Fee				MONEY,
		Discount		MONEY,
		DiscountRate	MONEY,
		DiscountRemark	NVARCHAR(4000),
		Rebate			MONEY,
		RebateRate		MONEY,
		RebateRemark	NVARCHAR(4000),
		NegativeFee		MONEY,
		Minfee			MONEY,
		IsChargedByMinFee BIT
	)
	INSERT INTO #AmountToCompany(PartyId,ProductId,Winloss,Fee,NegativeFee,Minfee,IsChargedByMinFee,Discount,DiscountRate,DiscountRemark,Rebate,RebateRate,RebateRemark)
	EXEC dbo.LA_AmountToCompanySel @FromDate,@ToDate,@PartyId,@ProductCodes,@BaseCurrency

	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			DECIMAL(9,8)
	)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)
	-- End region

	-- Region: Get Amount by Product
	DECLARE @Result TABLE(ProductId INT, AmountToCompany MONEY)

	-- include BA
	IF EXISTS(SELECT * FROM @Products WHERE ProductId = @BA)
	BEGIN
		INSERT INTO @Result(ProductId, AmountToCompany)
		(
			SELECT b.ProductId, SUM(((-ISNULL(b.MemberWL, 0) * p.Rate) - ISNULL(b.CommissionA, 0)) * e.Rate)
			FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
					INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
					INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
														AND p.LicenseeId = b.SiteId
														AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
			WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate)
					AND (b.CurrencyID <> 20)
					AND b.customercategory NOT IN (27, 28)
					AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
					AND b.ProductId = @BA
			GROUP BY b.ProductId
		)
	END
	
	IF EXISTS(SELECT * FROM @Products WHERE ProductId = @CB)
	BEGIN
		-- Region: include CB
		SELECT	rptDate,
				CurrencyId,
				SUM(Turnover) Turnover,
				SUM(CASE WHEN ISNULL(b.TicketType, 0) = 0 THEN b.Turnover ELSE b.ExtraAmount END) TurnoverForCommision,
				SUM(ISNULL(WinPrizeAmount,0)) WinningPrize,
				SUM(ISNULL(CashOutAmount,0)) CashOut,
				SUM(ISNULL(BuyBackAmount,0)) CashInAmount,
				CAST(0 AS MONEY) CommisionShare,
				CAST(0 AS MONEY) CashInShare
		INTO #TempDataCB
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		JOIN @PartyChargeInfo cb ON b.SiteID = cb.LicenseeId AND b.ProductId = cb.ProductID AND b.rptDate BETWEEN cb.FromDate AND cb.ToDate
		WHERE b.ProductId = @CB
			AND b.StatusId NOT IN (-1, 101, 102, 103)
			AND CustomerCategory NOT IN (27, 28)
			AND CurrencyId <> 20
			AND cb.TypeId = @CommChargeType -- to remove duplicate we use one of (6,7)
		GROUP BY rptdate, CurrencyId
	
		UPDATE #TempDataCB SET
			CommisionShare = td.TurnoverForCommision * cm.Rate,
			CashInShare = td.CashInAmount * ci.Rate
		FROM #TempDataCB td
		JOIN @PartyChargeInfo AS cm ON cm.ProductID = @CB AND cm.TypeId = @CommChargeType AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate)
		JOIN @PartyChargeInfo AS ci ON cm.ProductID = @CB AND ci.TypeId = @CashInShareChargeType AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate)

		INSERT INTO @Result(ProductId, AmountToCompany)
		SELECT @CB, SUM((Turnover - WinningPrize - Cashout - CommisionShare - CashInShare) * e.Rate)
		FROM #TempDataCB tcb
		INNER JOIN #Exchange e ON tcb.rptDate = e.ExchangeDate AND tcb.CurrencyId = e.ExchangeID

		DROP TABLE #TempDataCB
		-- End region: include CB
	END

	IF EXISTS(SELECT * FROM @Products WHERE ProductId = @CO)
	BEGIN
		-- Region: include CO
		;WITH CO AS (
			SELECT b.Winlostdate, b.Currency,
				SUM(b.BuyBackAmt) AS BuyBackAmountSB,
				SUM(b.BABuyBackAmt) AS BuyBackAmountBA,
				SUM(b.TicketPayout) AS TicketsPayout,
				SUM(b.BuyBackAmt * p.Rate) AS CashoutCommission
			FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON b.SiteId = p.LicenseeId AND b.ProductId = p.ProductID AND b.Winlostdate BETWEEN p.FromDate AND p.ToDate
			WHERE b.Winlostdate BETWEEN p.FromDate AND p.ToDate
				AND b.ProductID = @CO
				AND b.Currency <> 20
				AND b.RoleID = 1 -- Member Level
			GROUP BY b.Winlostdate, b.Currency
		)
		INSERT INTO @Result(ProductId, AmountToCompany)
		SELECT @CO, SUM((TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) * e.Rate)
		FROM CO INNER JOIN #Exchange e ON CO.Winlostdate = e.ExchangeDate AND CO.Currency = e.ExchangeID
		-- End region: include CO
	END

	-- amount to company(licensing fee) - discount
	INSERT INTO @Result(ProductId, AmountToCompany)
	SELECT ProductId, CASE WHEN NegativeFee < 0 THEN NegativeFee ELSE NegativeFee - Discount END
	FROM #AmountToCompany

	-- include no ticket product
	INSERT INTO @Result
	SELECT p.ProductId, 0 FROM @Products p
	WHERE p.ProductId NOT IN (SELECT r.ProductId FROM @Result r)

	DECLARE @Remark NVARCHAR(4000) = (SELECT TOP 1 x.RebateRemark FROM #AmountToCompany x WHERE ISNULL(x.RebateRemark,'') <> '')

	SELECT ISNULL(@Remark,'')		AS Remark,
		@ToDate						AS ReportDate,
		@BaseCurrency				AS CurrencyName,
		SUM(ISNULL(d.Rebate, 0))	AS TotalRebate,
		SUM(ISNULL(d.Fee, rs.AmountToCompany) - ISNULL(d.Discount,0)) AS TotalAmount
	FROM @Result rs
	LEFT JOIN #AmountToCompany d ON d.ProductId = rs.ProductId

	SELECT r.ProductId,ISNULL(r.AmountToCompany,0) FROM @Result r

	DROP TABLE #Exchange
	DROP TABLE #AmountToCompany
END
GO