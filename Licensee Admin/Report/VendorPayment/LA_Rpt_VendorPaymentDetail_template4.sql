/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template4]
	@PartyIds			VARCHAR(4000),
	@ProductID			INT,
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20),
	@TimeZoneId			INT
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template4 - Template for Exchange product, including some specific info such as: Licensee / Customer Comm)
 * Revisions
	- 20210615@Danny: Initialize SP [#168387]
 */

BEGIN
	SET NOCOUNT ON
-- Region: Charge Info	
	DECLARE @ProductCode VARCHAR(50)
	SELECT @ProductCode = ProductPrefix FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @ProductID

	DECLARE @ChargeInfos AS TABLE (
		PartyId		INT,
		PartyName	VARCHAR(100),
		ParentId	INT,
		ParentName	VARCHAR(100),	
		LicenseeId	INT,
		ProductID	INT,
		Rate		MONEY,		
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME)	
	
	DECLARE @PartyCharge3rdInfo AS TABLE (		
			LicenseeId	INT,
			Rate		MONEY,			
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			ProductID	INT
			)
	
	DECLARE @PartyList AS TABLE (PartyId INT, PartyName	VARCHAR(100), BranchName VARCHAR(100), ParentId	INT, ParentName VARCHAR(100))

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel

	UPDATE p
	SET p.ParentName = pa.PartyName
	FROM @PartyList p
		INNER JOIN @PartyList pa ON pa.ParentId = 0 AND p.ParentId = pa.PartyId

	INSERT INTO @ChargeInfos(PartyId, LicenseeId, ParentID, Rate, Fromdate, Todate, ProductID, PartyName, ParentName)
	(
		SELECT	ci.PartyID, ci.LicenseeID, p.ParentID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.ProductID, p.PartyName, p.ParentName
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1) ci	
			INNER JOIN @PartyList p ON ci.PartyID = p.PartyID	
		WHERE	DI_Rate > 0 AND ci.ChargeType = 1 -- get PT
	)
	-- Endregion	

	INSERT INTO @PartyCharge3rdInfo( LicenseeId, Rate, FromDate, ToDate, ProductID )	
	(
		SELECT DISTINCT p.LicenseeID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.ProductID
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') ci	
			INNER JOIN @ChargeInfos p ON ci.IsParent = 0 AND p.PartyID = ci.PartyId		
		WHERE ci.ChargeType = 1 AND ci.IsDeposit = 1
	)

	INSERT INTO @PartyCharge3rdInfo( LicenseeId, Rate, FromDate, ToDate, ProductID )	
	(
		SELECT DISTINCT p.LicenseeID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.ProductID
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') ci	
			INNER JOIN @ChargeInfos p ON ci.IsParent = 1 AND p.ParentID = ci.PartyId		
		WHERE ci.ChargeType = 1 AND ci.IsDeposit = 1
			AND NOT EXISTS (SELECT 1 FROM @PartyCharge3rdInfo ci WHERE ci.LicenseeId = p.LicenseeId)
	)	
	-- Endregion
	
	-- Region: #Result
	CREATE TABLE #Result (
		PartyID		INT,
		PartyName	NVARCHAR(100),
		ParentId	INT,
		ParentName	VARCHAR(100),	
		Winlossdate DATETIME,
		CurrencyId	INT,
		Turnover	MONEY,
		TotalTrans	INT,
		CustomerWinLoss MONEY,
		CustomerComm	MONEY,
		LicenseeComm	MONEY,
		LicenseeWinloss MONEY,
		LicensingFee	 MONEY,
		PayToSupplier	MONEY)	
	

	IF @TimeZoneId = 1 
	BEGIN
		INSERT INTO #Result (PartyID,PartyName,ParentId,ParentName,Winlossdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,CustomerComm,LicenseeComm,LicenseeWinloss,LicensingFee,PayToSupplier)
		SELECT ci.PartyId,
			ci.PartyName,
			ci.ParentId,
			ci.ParentName,
			b.rptDate,
			b.CurrencyId,
			SUM(b.Turnover) AS Turnover,
			SUM(b.BetCount) AS TotalTrans,
			SUM(b.MemberWL) AS CustomerWinLoss,
			SUM(b.CommissionP) AS CustomerComm,
			SUM(b.CommissionA) AS LicenseeComm,
			SUM(-(b.MemberWL + b.CommissionP)) AS LicenseeWinloss,
			SUM((-b.MemberWL * ci.Rate) - (b.CommissionA + b.CommissionP)) AS LicensingFee,
			SUM((-b.MemberWL * rd.Rate) - (b.CommissionA + b.CommissionP)) AS PayToSupplier
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN @PartyCharge3rdInfo rd ON b.ProductID = rd.ProductID
														AND b.SiteID = rd.LicenseeID
														AND (b.rptDate BETWEEN rd.FromDate AND rd.ToDate)	
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND  b.ProductID = @ProductID  AND
			b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 AND b.CustomerCategory NOT IN (27,28)
		GROUP BY b.rptDate, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId
	END
	ELSE
	BEGIN
		INSERT INTO #Result (PartyID,PartyName,ParentId,ParentName,Winlossdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,CustomerComm,LicenseeComm,LicenseeWinloss,LicensingFee,PayToSupplier)
		SELECT ci.PartyId,
			ci.PartyName,
			ci.ParentId,
			ci.ParentName,
			b.rptDate,
			b.CurrencyId,
			SUM(b.Turnover) AS Turnover,
			SUM(b.BetCount) AS TotalTrans,
			SUM(b.Winloss) AS CustomerWinLoss,
			SUM(b.PComm) AS CustomerComm,
			SUM(b.AComm) AS LicenseeComm,
			SUM(-(b.Winloss + b.PComm)) AS LicenseeWinloss,
			SUM((-b.Winloss * ci.Rate) - (b.AComm + b.PComm)) AS LicensingFee,
			SUM((-b.Winloss * rd.Rate) - (b.AComm + b.PComm)) AS PayToSupplier
		FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
			INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN @PartyCharge3rdInfo rd ON b.SiteID = rd.LicenseeID AND b.RptDate3rd BETWEEN rd.FromDate AND rd.ToDate
		WHERE b.RptDate BETWEEN DATEADD(DAY,-1,@FromDate) AND DATEADD(DAY,1,@ToDate)
			AND b.RptDate3rd BETWEEN @FromDate AND @ToDate 
			AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20
			AND b.BettypeID in (Select Bettype FROM LA_f_BettypeProductMapping(0,@ProductCode))
		GROUP BY b.rptDate, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId
	END
	-- EndRegion
	
	-- Region: Exchange
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeId = 92 THEN 'HID' 
															WHEN ExchangeId = 51 THEN 'INH' ELSE Code 
													   END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End Region
	
	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		CustomerComm	MONEY,
		LicenseeComm	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		Currency		VARCHAR(20)
	)

	-- Region: Calculate Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		CustomerComm	MONEY,
		LicenseeComm	MONEY,
		CustomerTotal	MONEY,	
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	
	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,CustomerComm,LicenseeComm,LicenseeWinLoss,LicensingFee,PayToSupplier)
		SELECT @tempCurrency, CASE WHEN td.PartyID = 14 THEN 14 ELSE td.ParentId END ParentId,
			SUM(td.TotalTrans) TotalTrans,
			SUM(td.Turnover * e.BaseCurrencyRate) Turnover, 
			SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss, 
			SUM(td.CustomerComm * e.BaseCurrencyRate) CustomerComm,
			SUM(td.LicenseeComm * e.BaseCurrencyRate) LicenseeComm,
			SUM(td.LicenseeWinLoss * e.BaseCurrencyRate) LicenseeWinLoss,
			SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
			SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier
		FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e 
		ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.Winlossdate
		GROUP BY CASE WHEN td.PartyID = 14 THEN 14 ELSE td.ParentId END 

		INSERT INTO @GrandTotal (CurrencyName, TotalTrans, Turnover, CustomerWinLoss, CustomerComm, LicenseeComm, CustomerTotal, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(CustomerComm),
			SUM(LicenseeComm),
			-SUM(LicenseeWinLoss),
			SUM(LicenseeWinLoss),
			SUM(LicensingFee),
			SUM(PayToSupplier),
			SUM(LicensingFee - PayToSupplier)
		FROM @Total
		WHERE Currency = @tempCurrency
		GROUP BY Currency

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END	
	-- End Region

	BEGIN
		-- Result
		SELECT r.PartyId,
			r.PartyName,
			r.ParentId,
			r.ParentName,
			r.WinLossDate,
			r.CurrencyId,			 
			e.CurrencyCode AS CurrencyName,
			r.TotalTrans,
			-- base
			CAST(r.Turnover * e.Rate AS MONEY) AS Turnover,
			CAST(r.CustomerWinLoss * e.Rate AS MONEY) AS CustomerWinLoss,
			CAST(r.CustomerComm * e.Rate AS MONEY) AS CustomerComm,
			CAST(r.LicenseeComm * e.Rate AS MONEY) AS LicenseeComm,
			CAST(LicenseeWinLoss * e.Rate AS MONEY) AS LicenseeWinLoss,
			CAST(r.LicensingFee * e.Rate AS MONEY) AS LicensingFee,
			CAST(r.PayToSupplier * e.Rate AS MONEY) AS PayToSupplier,
			CAST((r.LicensingFee - r.PayToSupplier) * e.Rate AS MONEY) AS CompanyIncome,
			-- original
			r.Turnover AS TurnoverOriginal,
			r.CustomerWinLoss AS CustomerWinLossOriginal,
			r.CustomerComm AS CustomerCommOriginal,
			r.LicenseeComm AS LicenseeCommOriginal,
			-(r.LicenseeWinLoss) AS CustomerTotalOriginal,
			r.LicenseeWinLoss AS LicenseeWinLossOriginal,
			r.LicensingFee AS LicensingFeeOriginal,
			r.PayToSupplier AS PayToSupplierOriginal,
			(r.LicensingFee - r.PayToSupplier) AS CompanyIncomeOriginal
		FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate

		-- Grand Total
		SELECT * FROM @GrandTotal
		
		-- Total
		SELECT PartyId,
			TotalTrans,
			Turnover,
			CustomerWinLoss,	
			CustomerComm,
			LicenseeComm,
			LicenseeWinLoss,
			LicensingFee,
			PayToSupplier,
			(LicensingFee - PayToSupplier) AS CompanyIncome
		FROM @Total t
		WHERE Currency = @BaseCurrencyName
	END
	-- End Region

	DROP TABLE #Exchange
	DROP TABLE #Result
END
GO