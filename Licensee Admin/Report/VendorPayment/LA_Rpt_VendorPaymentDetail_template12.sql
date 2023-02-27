/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template12]
	@PartyIds			VARCHAR(4000)
	,@ProductID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@TicketType		TINYINT
	,@BaseCurrencyName	VARCHAR(20)
	,@TimeZoneId		INT
	,@PlatformId		TINYINT = 0
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template12 - Template for Muay Thai product, including some specific info such as: Licnesee Comm, Com Sharing, WL Sharing)
 * Revisions
	- 20210615@Danny: Initialize SP [#168387]
	- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
	- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
 */

BEGIN
	SET NOCOUNT ON
	-- Region: Charge Info
	DECLARE @PartyChargeInfo AS TABLE (
		ChargeId	INT,
		PartyId		INT,
		LicenseeId	INT,
		IsDeposit   BIT,
		ProductID	INT,
		Rate		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME
	)

	DECLARE @ShareRate MONEY = 0.03

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	INSERT INTO @PartyChargeInfo(ChargeId, PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate)
	(
		SELECT	ChargeID, PartyID, LicenseeID, isDeposit, ProductID, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 0)
	)
	-- End region

	-- Region: Party List
	DECLARE @PartyList AS TABLE (
		PartyId		INT,
		PartyName	VARCHAR(100),
		BranchName	VARCHAR(100),
		ParentId	INT
	)

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel

	UPDATE @PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0

	-- Endregion

	-- Region: Get exchange rate info
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(65),
		Rate			FLOAT
	)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeID = 51 THEN 'INH' 
															WHEN ExchangeID = 92 THEN 'HID' 
															ELSE Code END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End region

	-- Region: Get Winloss data
	CREATE	TABLE #TempData (
		LicenseeId	INT,
		PartyId		INT,
		IsDeposit	BIT,
		rptDate		DATETIME,
		CurrencyId	INT,
		TotalTrans	INT,
		Turnover	MONEY,
		MemberWL	MONEY,
		WLShare		MONEY,
		LicComm		MONEY,
		CommShare	MONEY,
		AmtLicensee MONEY
	)

	-- Cut of date is 2017-10-01 - Just support single ticket
	DECLARE @CutOfDate		SMALLDATETIME,
			@TmpFromDate	SMALLDATETIME,
			@TmpToDate		SMALLDATETIME

	SELECT @CutOfDate = '2017-09-30'
	SELECT @TmpFromDate = CASE WHEN @FromDate <= @CutOfDate THEN DATEADD(DAY,1,@CutOfDate) ELSE @FromDate END
	SELECT @TmpToDate = CASE WHEN @ToDate >= @CutOfDate THEN @CutOfDate ELSE @ToDate END

	IF @ToDate > @CutOfDate -- New Data
	BEGIN
		INSERT INTO #TempData (LicenseeId, PartyId, IsDeposit, rptDate, CurrencyId, TotalTrans, Turnover, MemberWL, WLShare, LicComm, CommShare, AmtLicensee)
		(
			SELECT	b.SiteID,
					p.PartyId,
					p.IsDeposit,
					b.rptDate,
					b.CurrencyID,
					SUM(ISNULL(b.BetCount, 0)) TotalTrans,
					SUM(ISNULL(b.Turnover, 0)) Turnover,
					SUM(ISNULL(b.AdjustedCustomerWL, 0)) MemberWL,
					SUM(ISNULL(b.AdjustedCustomerWL, 0) * (- @ShareRate)) WLShare,
					SUM(ISNULL(b.AdjustedCommissionS, 0)) LicComm,
					SUM(ISNULL(b.AdjustedCommShare, 0)) CommShare,
					SUM(CASE WHEN p.IsDeposit = 0
							THEN ISNULL(b.AdjustedLicenseeWL, 0)
							ELSE ISNULL(-b.AdjustedCustomerWL, 0) * ISNULL(cr.Rate, p.Rate)
						END) AmtLicensee
			FROM	bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
					INNER JOIN @PartyChargeInfo p ON b.ProductID = p.ProductID
													AND b.SiteID = p.LicenseeId
													AND b.rptDate BETWEEN p.FromDate AND p.ToDate
					LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeId = cr.ChargeID AND cr.CurrencyID = b.CurrencyId
			WHERE	b.rptDate BETWEEN @TmpFromDate AND @ToDate
					AND (b.CurrencyID <> 20)
					AND b.StatusId BETWEEN 111 AND 113
					AND b.customercategory NOT IN (27, 28)
					AND b.SportType = 44 -- MuayThai
					AND ( @TicketType = 3
						OR (@TicketType = 1 AND ISNULL(b.IsParlay, 0) = 0)
						OR (@TicketType = 2 AND ISNULL(b.IsParlay, 0) = 1)
						)
			GROUP BY b.rptdate, b.SiteId, b.CurrencyID, p.PartyId, p.IsDeposit
		)
	END

	IF @FromDate <= @CutOfDate AND @TicketType IN (1, 3)-- Old data
	BEGIN
		INSERT INTO #TempData (LicenseeId, PartyId, IsDeposit, rptDate, CurrencyId, TotalTrans, Turnover, MemberWL, WLShare, LicComm, CommShare, AmtLicensee)
		(
			SELECT	b.SiteID,
					p.PartyId,
					p.IsDeposit,
					b.rptDate,
					b.CurrencyID,
					SUM(ISNULL(b.BetCount, 0)) TotalTrans,
					SUM(ISNULL(b.Turnover, 0)) Turnover,
					SUM(ISNULL(b.CustomerWL, 0)) MemberWL,
					SUM(ISNULL(b.WLShare, 0)) WLShare,
					SUM(ISNULL(b.CommissionS, 0)) LicComm,
					SUM(ISNULL(b.CommShare, 0)) CommShare,
					SUM(CASE WHEN p.IsDeposit = 0
							THEN ISNULL(b.LicenseeWL, 0)
							ELSE ISNULL(-b.CustomerWL, 0) * ISNULL(cr.Rate, p.Rate)
						END) AmtLicensee
			FROM	bodb_LicenseeReport.dbo.rpt_BettingBySport b WITH (NOLOCK)
					INNER JOIN @PartyChargeInfo p ON b.ProductID = p.ProductID
													AND b.SiteID = p.LicenseeId
													AND b.rptDate BETWEEN p.FromDate AND p.ToDate
					LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = p.ChargeId AND cr.CurrencyID = b.CurrencyId
			WHERE	b.rptDate BETWEEN @FromDate AND @TmpToDate
					AND (b.CurrencyID <> 20)
					AND b.StatusId BETWEEN 111 AND 113
					AND b.customercategory NOT IN (27, 28)
					AND b.SportType = 44 -- Muay Thai
			GROUP BY b.rptdate, b.SiteId, b.CurrencyID, p.PartyId, p.IsDeposit
		)
	END

	-- EndRegion

	-- Region: Result data
	CREATE TABLE #Result (
		PartyId				INT,
		PartyName			VARCHAR(100),
		ParentId			INT,
		ParentName			VARCHAR(100),
		WinLossDate			DATETIME,
		CurrencyId			INT,
		TotalTrans			INT,
		Turnover			MONEY,
		CustomerWinLoss		MONEY,
		WinLossShare		MONEY,
		LicenseeComm		MONEY,
		CommissionShare		MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	INSERT INTO #Result (PartyId, PartyName, WinLossDate, CurrencyId, ParentId, ParentName, TotalTrans, Turnover, CustomerWinLoss, WinLossShare, LicenseeComm, CommissionShare, LicensingFee)
	SELECT	p.PartyId, 
			p.PartyName, 
			td.rptDate, 
			td.CurrencyId,
			pa.PartyId, 
			pa.PartyName, 
			SUM(td.TotalTrans),
			SUM(td.Turnover),
			SUM(td.MemberWL),
			SUM(td.WLShare),
			SUM(td.LicComm),
			SUM(td.CommShare),
			SUM(td.AmtLicensee)
	FROM #TempData td
		INNER JOIN @PartyList p ON td.PartyId = p.PartyID
		INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId	
	GROUP BY p.PartyId, p.PartyName, td.rptDate, td.CurrencyId,pa.PartyId, pa.PartyName

	UPDATE #Result
	SET PayToSupplier = WinLossShare + CommissionShare

	UPDATE #Result
	SET CompanyIncome = LicensingFee - PayToSupplier
	-- EndRegion

	-- Region: Grand total data
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	-- support THB
	INSERT INTO @BaseCurrencies(Id, Name)VALUES(4,'THB')

	CREATE TABLE #Total (
		PartyId			INT,
		Currency		VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss		MONEY,
		WinLossShare		MONEY,
		LicenseeComm		MONEY,
		CommissionShare		MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)

	CREATE TABLE #GrandTotal (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss		MONEY,
		WinLossShare		MONEY,
		LicenseeComm		MONEY,
		CommissionShare		MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)

	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)

		;WITH TotalByParty AS(
			SELECT CASE WHEN td.PartyID = 14 THEN 14 ELSE td.ParentId END ParentId, td.PartyId,
				SUM(td.TotalTrans) TotalTrans,
				SUM(td.Turnover*e.BaseCurrencyRate) Turnover,
				SUM(td.CustomerWinLoss*e.BaseCurrencyRate) CustomerWinLoss,
				SUM(td.WinLossShare*e.BaseCurrencyRate) WinLossShare,
				SUM(td.LicenseeComm*e.BaseCurrencyRate) LicenseeComm,
				SUM(td.CommissionShare*e.BaseCurrencyRate) CommissionShare,
				SUM(td.LicensingFee*e.BaseCurrencyRate) LicensingFee
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
			GROUP BY CASE WHEN td.PartyID = 14 THEN 14 ELSE td.ParentId END, td.PartyId
		)
		INSERT INTO #Total (PartyId,Currency,TotalTrans,Turnover,CustomerWinLoss,WinLossShare,LicenseeComm,CommissionShare,LicensingFee, PayToSupplier, CompanyIncome)
		SELECT ParentId, @tempCurrency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(WinLossShare),
			SUM(LicenseeComm),
			SUM(CommissionShare),
			SUM(LicensingFee),
			SUM(WinLossShare + CommissionShare),
			SUM(LicensingFee - WinLossShare - CommissionShare)
		FROM TotalByParty
		GROUP BY ParentId

		INSERT INTO #GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,WinLossShare,LicenseeComm,CommissionShare,LicensingFee, PayToSupplier, CompanyIncome)
		SELECT @tempCurrency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(WinLossShare),
			SUM(LicenseeComm),
			SUM(CommissionShare),
			SUM(LicensingFee),
			SUM(PayToSupplier),
			SUM(CompanyIncome)
		FROM #Total
		WHERE Currency = @tempCurrency
		GROUP BY Currency

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END
	--EndRegion

	SELECT 
		r.PartyId,
		r.PartyName,
		CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId,
		CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE r.ParentName END ParentName,
		r.WinLossDate,
		e.CurrencyCode AS CurrencyName,
		-- Select by origin currency
		r.TotalTrans,
		r.Turnover AS TurnoverOriginal,
		CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLossOriginal,
		CAST((r.WinLossShare) AS MONEY) AS WinLossShareOriginal,
		CAST((r.LicenseeComm) AS MONEY) AS LicenseeCommOriginal,
		CAST((r.CommissionShare) AS MONEY) AS CommissionShareOriginal,
		CAST((r.LicensingFee) AS MONEY) AS LicensingFeeOriginal,
		CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
		CAST((r.CompanyIncome) AS MONEY) AS  CompanyIncomeOriginal,
		-- Select by base currency
		r.Turnover * e.Rate  AS Turnover,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST((r.WinLossShare * e.Rate) AS MONEY) AS WinLossShare,
		CAST((r.LicenseeComm * e.Rate) AS MONEY) AS LicenseeComm,
		CAST((r.CommissionShare * e.Rate) AS MONEY) AS CommissionShare,
		CAST((r.LicensingFee * e.Rate) AS MONEY) AS LicensingFee,
		CAST((r.PayToSupplier * e.Rate)  AS MONEY) AS PayToSupplier,
		CAST((r.CompanyIncome * e.Rate)  AS MONEY)  AS  CompanyIncome
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate

	;WITH TotalByParty AS(
			SELECT ParentId, td.PartyId, td.PartyName,
				SUM(td.TotalTrans) TotalTrans,
				SUM(td.Turnover * e.Rate) Turnover,
				SUM(td.CustomerWinLoss * e.Rate) CustomerWinLoss,
				SUM(td.WinLossShare * e.Rate) WinLossShare,
				SUM(td.LicenseeComm * e.Rate) LicenseeComm,
				SUM(td.CommissionShare * e.Rate) CommissionShare,
				SUM(td.LicensingFee * e.Rate) LicensingFee,
				SUM(td.PayToSupplier * e.Rate) PayToSupplier,
				SUM(td.CompanyIncome * e.Rate) CompanyIncome
			FROM #Result td INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND td.WinLossDate = e.ExchangeDate
			GROUP BY td.ParentId, td.PartyId, td.PartyName
		)

	SELECT CASE WHEN PartyId = 14 THEN 14 ELSE ParentId END ParentId,
		PartyId,
		PartyName,
		TotalTrans,
		Turnover,
		CustomerWinLoss,
		WinLossShare,
		LicenseeComm,
		CommissionShare,
		LicensingFee,
		PayToSupplier,
		CompanyIncome
	FROM TotalByParty

	SELECT * FROM #GrandTotal

	SELECT * FROM #Total WHERE Currency = @BaseCurrencyName

	DROP TABLE #TempData
	DROP TABLE #Exchange
	DROP TABLE #Result
	DROP TABLE #GrandTotal
	DROP TABLE #Total
END
GO