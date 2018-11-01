/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Rpt_ExchangeWinLoss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20)
AS
/*  
	 Created: 20180123@Parsons [#87754]
	 Task : Get report Exchange Win Loss
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180123@Parsons: Create Exchange Win Loss [#87754]
		- 20180508@Harper: Change PayToSupplier term of Exchange product [RedmineID: #94281]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180612@Scofield: Modify Exchange WL Report with Licensee charge comm [#96768]

	 Params:

	 Explannation: EXEC LA_Rpt_ExchangeWinLoss @FromDate='2018-05-01',@BaseCurrencyName='EUR',@ToDate='2018-05-25',@PartyIds='14,15,16,17'
*/
BEGIN		

	-- Region: Charge Info	
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
		FROM	dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'BX', 'OA', 1) ci	
			INNER JOIN @PartyList p ON ci.PartyID = p.PartyID	
		WHERE	DI_Rate > 0 AND ci.ChargeType = 1 -- get PT
	)
	-- Endregion	

	INSERT INTO @PartyCharge3rdInfo( LicenseeId, Rate, FromDate, ToDate, ProductID )	
	(
		SELECT DISTINCT p.LicenseeID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.ProductID
		FROM	dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'BX', 'OA') ci	
			INNER JOIN @ChargeInfos p ON ci.IsParent = 0 AND p.PartyID = ci.PartyId		
		WHERE ci.ChargeType = 1 AND ci.IsDeposit = 1
	)

	INSERT INTO @PartyCharge3rdInfo( LicenseeId, Rate, FromDate, ToDate, ProductID )	
	(
		SELECT DISTINCT p.LicenseeID, ci.DI_Rate, ci.Fromdate, ci.ToDate, ci.ProductID
		FROM	dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'BX', 'OA') ci	
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
	FROM bodb_LicenseeReport..rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId 
									AND b.ProductID = ci.ProductID 
									AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
		INNER JOIN @PartyCharge3rdInfo rd ON b.ProductID = rd.ProductID
													AND b.SiteID = rd.LicenseeID
													AND (b.rptDate BETWEEN rd.FromDate AND rd.ToDate)	
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
		b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 AND b.CustomerCategory NOT IN (27,28)
	GROUP BY b.rptDate, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId

	-- EndRegion
	
	-- Region: Exchange
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
		
	UPDATE #Exchange SET CurrencyCode = 'INH' WHERE ExchangeID = 51
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
		SELECT @tempCurrency, td.ParentId,
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
		GROUP BY td.ParentId

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

	-- Region: Select Data	
	IF @BaseCurrencyName = ''
	BEGIN		
		--Result 
		SELECT r.PartyId,
			r.PartyName,
			r.ParentId,
			r.ParentName,
			r.WinLossDate,
			r.CurrencyID,			 
			e.CurrencyCode AS CurrencyName,
			r.TotalTrans,
			r.Turnover,
			r.CustomerWinLoss,
			r.CustomerComm,
			r.LicenseeComm,
			r.LicenseeWinLoss,
			r.LicensingFee,
			r.PayToSupplier,
			(r.LicensingFee - r.PayToSupplier) AS CompanyIncome
		FROM #Result r 
		INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate

		-- Grand Total
		SELECT * FROM @GrandTotal	
	END	
	ELSE 
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

GRANT EXECUTE ON [dbo].[LA_Rpt_ExchangeWinLoss] TO [bodbAdminNet]
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_ExchangeWinLoss] TO [vnteam] 
GO