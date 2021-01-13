/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO
ALTER PROCEDURE [dbo].[LA_Rpt_PragmaticWinLoss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20)
AS
/*  
	 Created: 20180508@Parsons [#94108]
	 Task : Get report Pragmatic Win Loss
	 DB: DB052.bodb_licensee

	 Revisions:  
		- 20180508@Parsons: Integrate Pragmatic Win Loss [#94108]
		- 20190308@Parsons: Integrate PP promotion prize [#109014]
		- 20191204@Bruce: PP tournament [#123958]
		- 20200217@Mason: Set billing term by currency [#120005]
		- 20200302@Mason: Support HID currency [#128856]
		- 20200723@Parsons: Implement PP Jackpot [#137306]
		- 20200910@Parsons: Implement PP JP for Credit [#138984]
		- 20210112@Mason: Fix bug : Pay to Supplier is incorrect with other based currency [#147375]

	 Params:

	 Explannation: EXEC LA_Rpt_PragmaticWinLoss @BaseCurrencyName='EUR',@ToDate='2018-04-30 00:00:00',@PartyIds='14,15,17,19,20,23,29,39,40,42,44,46,47,52,53,56,58,60,65,68,70,71,72,73,76,79,80,81,82,84,85,86,87,89,90,91,92,93,95,97,100,101,24,31,34,35,36,37,38,41,59,66,67,74,75,88,16,22,26,27,45,49,54,99,25,30',@FromDate='2018-04-01 00:00:00'
*/
BEGIN	
	DECLARE  @Contribution INT = 4297,
			 @JackpotPrize INT = 4298,
			 @PPTournament INT = 4299,
			 @PromotionPrize INT = 4300

	-- Region: Charge Info	
	DECLARE @ChargeInfos AS TABLE (
		ChargeId	INT,
		PartyId		INT,
		LicenseeId	INT,
		isDeposit	BIT,
		ProductID	INT,
		Rate		MONEY,
		Rate3rd		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME)	
	
	-- get licenseeFee's charge rate
	INSERT INTO @ChargeInfos(ChargeId, PartyId, ProductID, LicenseeId, isDeposit, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT c.ChargeID, c.PartyID, c.ProductID, c.LicenseeID, ISNULL(c.isDeposit, 0) AS isDeposit,
			CASE WHEN ISNULL(c.isDeposit, 0) = 1 THEN c.DI_Rate ELSE 0 END,
			c.Fromdate, c.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'PP', 'OA', 1) c		
	)
	-- End region

	-- Region: Party List
	DECLARE @PartyList AS TABLE (PartyId INT, PartyName	VARCHAR(100), BranchName VARCHAR(100), ParentId	INT, ParentName VARCHAR(100))

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel

	UPDATE p
	SET p.ParentName = pa.PartyName
	FROM @PartyList p
	INNER JOIN @PartyList pa ON pa.ParentId = 0 AND p.ParentId = pa.PartyId

	DELETE p
	FROM @PartyList p
	WHERE NOT EXISTS (SELECT 1 FROM @ChargeInfos ci WHERE ci.PartyId = p.PartyId)
	-- Endregion	

	-- Region: update Rate3rd for Deposit's charge rate
	UPDATE ci
	SET Rate3rd = CI3rd.DI_Rate
	FROM @ChargeInfos ci
	INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
	INNER JOIN LA_f_ChargeInfo3rd (@FromDate, @ToDate, 'PP', 'OA') CI3rd ON p.ParentId = CI3rd.PartyID AND ci.ProductID = CI3rd.ProductID
	WHERE ISNULL(CI3rd.IsDeposit, 0) = 1
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
		WinPrizeAmount MONEY,
		Contribution	MONEY,
		JackpotPrize	MONEY,
		CustomerWinLoss MONEY,
		LicenseeWinloss MONEY,
		LicensingFee	MONEY,
		LicenseeChargeRate	MONEY,
		PayToSupplier	MONEY)

	-- Calculate for deposit
	;WITH cte_WinLossData AS
	(
		SELECT ci.PartyId,
			b.RptDate3rd,
			b.CurrencyId,
			b.SiteId,
			SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize,@PromotionPrize,@PPTournament) THEN 0 ELSE b.Turnover END) AS Turnover,
			SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize,@PromotionPrize,@PPTournament) THEN 0 ELSE b.BetCount END) AS TotalTrans,
			SUM(CASE WHEN b.BetTypeId IN (@PromotionPrize,@PPTournament) THEN b.Winloss ELSE 0 END) AS WinPrizeAmount,
			SUM(CASE WHEN b.BetTypeId = @Contribution THEN -b.AWinloss ELSE 0 END) AS LicenseeContribution,
			SUM(CASE WHEN b.BetTypeId = @Contribution THEN ProgressiveContribution ELSE 0 END) AS FullContribution,
			SUM(CASE WHEN b.BetTypeId = @JackpotPrize THEN b.Winloss ELSE 0 END) AS JackpotPrize,
			SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize,@PromotionPrize,@PPTournament) THEN 0 ELSE b.Winloss END) AS CustomerWinLoss,
			SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize,@PromotionPrize,@PPTournament) THEN 0 ELSE -b.Winloss END) AS LicenseeWinloss
		FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
			INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
		WHERE b.RptDate3rd BETWEEN @FromDate AND @ToDate AND
			b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20
			AND b.BetTypeId BETWEEN 4101 AND 4300
			AND ci.isDeposit = 1
		GROUP BY b.RptDate3rd, ci.PartyId, b.CurrencyId, b.SiteId
	)
	INSERT INTO #Result (PartyID,PartyName,ParentId,ParentName,Winlossdate,CurrencyId,Turnover,TotalTrans,WinPrizeAmount,Contribution,JackpotPrize,CustomerWinLoss,LicenseeWinloss,LicensingFee,LicenseeChargeRate,PayToSupplier)
	SELECT ci.PartyId,
		p.PartyName,
		p.ParentId,
		p.ParentName,
		b.RptDate3rd,
		b.CurrencyId,
		SUM(Turnover),
		SUM(TotalTrans),
		SUM(WinPrizeAmount),
		SUM(FullContribution),
		SUM(JackpotPrize),
		SUM(CustomerWinLoss),
		SUM(LicenseeWinloss),
		SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate) + LicenseeContribution - JackpotPrize - WinPrizeAmount) AS LicensingFee,
		SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate)) AS LicenseeChargeRate,
		SUM((LicenseeWinloss - FullContribution) * ci.Rate3rd) AS PayToSupplier
	FROM cte_WinLossData b
		INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
		INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeId AND cr.CurrencyID = b.CurrencyId
	GROUP BY b.RptDate3rd, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId
	-- EndRegion #Result
	
	-- Region: Charge Info	
	DECLARE @CreditChargeInfos AS TABLE (
		PartyId		INT,
		LicenseeId	INT,
		isDeposit	BIT,
		ProductID	INT,
		Rate		MONEY,
		Rate3rd		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME)	
	
	-- get licenseeFee's charge rate
	INSERT INTO @CreditChargeInfos(PartyId, ProductID, LicenseeId, isDeposit, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT c.PartyID, c.ProductID, c.LicenseeID, ISNULL(c.isDeposit, 0) AS isDeposit,
			CASE WHEN ISNULL(c.isDeposit, 0) = 1 THEN c.Rate ELSE 0 END,
			c.Fromdate, c.Todate
		FROM @ChargeInfos c
		WHERE c.isDeposit <> 1		
	)
	-- End region
	;WITH cte_WinLossData AS
	(
		SELECT ci.PartyId,
		b.RptDate3rd,
		b.CurrencyId,
		b.SiteId,
		SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize,@PromotionPrize,@PPTournament) THEN 0 ELSE b.Turnover END) AS Turnover,
		SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize,@PromotionPrize,@PPTournament) THEN 0 ELSE b.BetCount END) AS TotalTrans,
		SUM(CASE WHEN b.BetTypeId IN (@PromotionPrize,@PPTournament) THEN b.Winloss ELSE 0 END) AS WinPrizeAmount,
		SUM(CASE WHEN b.BetTypeId = @JackpotPrize THEN b.Winloss ELSE 0 END)												 AS JackpotPrize,
		SUM(CASE WHEN b.BetTypeId = @Contribution THEN ProgressiveContribution ELSE 0 END)									 AS FullContribution,
		SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize,@PromotionPrize,@PPTournament) THEN 0 ELSE b.Winloss END)  AS CustomerWinLoss,
		SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize,@PromotionPrize,@PPTournament) THEN 0 ELSE -b.Winloss END) AS LicenseeWinloss
	FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
		INNER JOIN @CreditChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
		INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
	WHERE b.RptDate3rd BETWEEN @FromDate AND @ToDate AND
		b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20
		AND b.BetTypeId BETWEEN 4101 AND 4300
		AND ci.isDeposit = 0
	GROUP BY b.RptDate3rd, ci.PartyId, b.CurrencyId, b.SiteId
	)

	INSERT INTO #Result (PartyID,PartyName,ParentId,ParentName,Winlossdate,CurrencyId,Turnover,TotalTrans,WinPrizeAmount,Contribution,JackpotPrize,CustomerWinLoss,LicenseeWinloss,LicensingFee,LicenseeChargeRate)
	SELECT ci.PartyId,
		p.PartyName,
		p.ParentId,
		p.ParentName,
		b.RptDate3rd,
		b.CurrencyId,
		SUM(Turnover),
		SUM(TotalTrans),
		SUM(WinPrizeAmount),
		SUM(FullContribution),
		SUM(JackpotPrize),
		SUM(CustomerWinLoss),
		SUM(LicenseeWinloss),
		0,0
	FROM cte_WinLossData b
		INNER JOIN @CreditChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
		INNER JOIN @PartyList p ON ci.PartyId = p.PartyId
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.LicenseeId AND cr.CurrencyID = b.CurrencyId
	GROUP BY b.RptDate3rd, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId	 
	-- EndRegion #Result

	-- Region: Exchange
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeID = 51 THEN 'INH' 
															WHEN ExchangeID = 92 THEN 'HID' 
															ELSE Code 
													   END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End Region
	
	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		WinPrizeAmount	MONEY,
		Contribution	MONEY,
		JackpotPrize	MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		Currency		VARCHAR(20)
	)

	-- Region: Calculate Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(Id INT, Name VARCHAR(20), IsApply BIT, IsCalculationTotal BIT)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		WinPrizeAmount	MONEY,
		Contribution	MONEY,
		JackpotPrize	MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)

	DECLARE @NumberOfTiers INT = 2

	-- Region Credit
	DECLARE @RateOfCredit AS TABLE (
		RowIndex TINYINT IDENTITY(1,1),
		PartyId			INT,
		Rate			MONEY,
		MinAmount		MONEY,
		MaxAmount		MONEY,
		BaseCurrencyId	SMALLINT
	)
	INSERT INTO @RateOfCredit(PartyId, Rate, MinAmount, MaxAmount, BaseCurrencyId)
	SELECT DISTINCT	ci.FromParty, ci.Rate, MinAmount, MaxAmount, BaseCurrencyId
	FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
	INNER JOIN @CreditChargeInfos ci2 ON ci.FromParty = ci2.PartyId 
	WHERE ci2.isDeposit = 0 AND ci.ProductID = 32
	ORDER BY FromParty, MaxAmount DESC

	-- Region TotalAmountOfCreditGroup
	DECLARE @CreditBaseCurrencyName VARCHAR(10), @CreditBaseCurrencyId INT
	SELECT TOP 1 @CreditBaseCurrencyName = Name, @CreditBaseCurrencyId = BaseCurrencyId FROM @BaseCurrencies b INNER JOIN @RateOfCredit c ON c.BaseCurrencyId=b.Id

		-- Region: @TotalAmount_BasedOn_CreditBaseCurrencyName
	DECLARE @TotalAmount_BasedOn_CreditBaseCurrencyName MONEY, @TotalAmountWinLossBase MONEY
	SELECT @TotalAmount_BasedOn_CreditBaseCurrencyName = SUM((-r.CustomerWinLoss - Contribution) * e.BaseCurrencyRate)
	FROM #Result r
	INNER JOIN (SELECT DISTINCT PartyId FROM @RateOfCredit) roc ON r.PartyID = roc.PartyId
	INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CreditBaseCurrencyName) e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.Winlossdate
		-- End region: @TotalAmount_BasedOn_CreditBaseCurrencyName
	--Endregion TotalAmountOfCreditGroup

	-- Region Update PayToSupplier for #Result
	;WITH SumByPropressiveAmount AS(
		SELECT  r.PartyId,CurrencyId,Winlossdate,
				SUM(CASE 
					WHEN ((r.LicenseeWinloss - Contribution) * e.BaseCurrencyRate) > MaxAmount THEN MaxAmount 
					WHEN ((r.LicenseeWinloss - Contribution) * e.BaseCurrencyRate  - MinAmount) > 0 THEN ((r.LicenseeWinloss - Contribution) * e.BaseCurrencyRate - MinAmount)
					WHEN (r.LicenseeWinloss - Contribution) * e.BaseCurrencyRate < 0 AND roc.RowIndex % @NumberOfTiers = 0 THEN (r.LicenseeWinloss - Contribution) * e.BaseCurrencyRate 
					ELSE 0 END  * roc.Rate / e.BaseCurrencyRate)  AS ProgressiveAmount
		FROM #Result r 
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CreditBaseCurrencyName) e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.Winlossdate
		INNER JOIN @RateOfCredit roc ON r.PartyID = roc.PartyID
		GROUP BY r.PartyId,CurrencyId,Winlossdate
	)
	UPDATE r
	SET r.PayToSupplier = ProgressiveAmount
	FROM #Result r
	INNER JOIN SumByPropressiveAmount s ON r.PartyId = s.PartyID AND r.CurrencyId = s.CurrencyId AND r.Winlossdate = s.Winlossdate
	-- Endregion Update PayToSupplier for #Result

	--Endregion Credit
	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		
		;WITH TotalByParty AS(
			SELECT td.ParentId,
				SUM(td.TotalTrans)								TotalTrans,
				SUM(td.Turnover * e.BaseCurrencyRate)			Turnover, 
				SUM(td.WinPrizeAmount * e.BaseCurrencyRate)		WinPrizeAmount,
				SUM(ISNULL(td.Contribution, 0) * e.BaseCurrencyRate)		Contribution,
				SUM(ISNULL(td.JackpotPrize, 0) * e.BaseCurrencyRate)		JackpotPrize,
				SUM(td.CustomerWinLoss * e.BaseCurrencyRate)	CustomerWinLoss, 
				SUM(td.LicenseeWinLoss * e.BaseCurrencyRate)	LicenseeWinLoss, 
				SUM(td.LicensingFee * e.BaseCurrencyRate)		LicensingFee,
				SUM(ISNULL(td.LicenseeChargeRate, 0) * e.BaseCurrencyRate) LicenseeChargeRate,
				SUM(td.PayToSupplier * e.BaseCurrencyRate)		PayToSupplier
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e 
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
			GROUP BY td.ParentId, td.PartyId
		)
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,WinPrizeAmount,Contribution,JackpotPrize,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier)
		SELECT @tempCurrency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(WinPrizeAmount),
			SUM(Contribution),
			SUM(JackpotPrize),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN ParentId = 999 THEN 0 -- Credit Licensee: always is 0
			         ELSE CASE WHEN LicenseeChargeRate < 0 THEN 0 ELSE LicenseeChargeRate END + Contribution - JackpotPrize - WinPrizeAmount
				END),
			SUM(PayToSupplier)
		FROM TotalByParty
		GROUP BY ParentId

		-- Region update Total of Creadit
			;WITH SumByPropressiveAmount AS(
				SELECT  r.PartyId,
						SUM(CASE 
							WHEN @TotalAmount_BasedOn_CreditBaseCurrencyName > MaxAmount THEN MaxAmount * e.BaseCurrencyRate 
							WHEN @TotalAmount_BasedOn_CreditBaseCurrencyName  - MinAmount > 0 THEN (r.LicenseeWinloss - Contribution) - (MinAmount * e.BaseCurrencyRate)
							WHEN @TotalAmount_BasedOn_CreditBaseCurrencyName < 0 AND roc.RowIndex % @NumberOfTiers = 0 THEN r.LicenseeWinloss - Contribution
							ELSE 0 END  * roc.Rate)  AS ProgressiveAmount
				FROM @Total r 
				INNER JOIN @RateOfCredit roc ON RowIndex <= @NumberOfTiers
				INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@ToDate, @ToDate, @tempCurrency) e ON @CreditBaseCurrencyId = e.ExchangeID
				WHERE r.Currency = @tempCurrency AND r.PartyId = 999 
				GROUP BY r.PartyId 
			)
			UPDATE t
			SET PayToSupplier = ProgressiveAmount
			FROM @Total t
			INNER JOIN SumByPropressiveAmount s ON t.PartyId = s.PartyID
			WHERE t.Currency = @tempCurrency
		-- Endregion update Total of Creadit

		UPDATE @Total
		SET PayToSupplier = CASE WHEN PayToSupplier < 0 THEN 0 ELSE PayToSupplier END - WinPrizeAmount
		WHERE @tempCurrency = Currency

		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,WinPrizeAmount,Contribution,JackpotPrize,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(WinPrizeAmount),
			SUM(Contribution),
			SUM(JackpotPrize),
			SUM(CustomerWinLoss),
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

	-- Region: Select Result
	-- Currency report
		SELECT r.PartyId,
			r.PartyName,
			r.ParentId,
			r.ParentName,
			r.WinLossDate,
			r.CurrencyId,			 
			e.CurrencyCode AS CurrencyName,
			r.TotalTrans,
			-- base
			CAST(r.Turnover * e.Rate AS MONEY)			AS Turnover,
			CAST(r.WinPrizeAmount * e.Rate AS MONEY)	AS WinPrizeAmount,
			CAST(r.Contribution * e.Rate AS MONEY)		AS Contribution,
			CAST(r.JackpotPrize * e.Rate AS MONEY)		AS JackpotPrize,
			CAST(r.CustomerWinLoss * e.Rate AS MONEY)	AS CustomerWinLoss,
			CAST(LicenseeWinLoss * e.Rate AS MONEY)		AS LicenseeWinLoss,
			CAST(r.LicensingFee * e.Rate AS MONEY)		AS LicensingFee,
			CAST(r.LicenseeChargeRate * e.Rate AS MONEY)		AS LicenseeChargeRate,
			CAST((PayToSupplier - WinPrizeAmount) * e.Rate AS MONEY)		AS PayToSupplier,
			CAST((r.LicensingFee - (PayToSupplier - WinPrizeAmount)) * e.Rate AS MONEY) AS CompanyIncome,
			-- original
			r.Turnover			AS TurnoverOriginal,
			r.WinPrizeAmount	AS WinPrizeAmountOriginal,
			r.Contribution		AS ContributionOriginal,
			r.JackpotPrize		AS JackpotPrizeOriginal,
			r.CustomerWinLoss	AS CustomerWinLossOriginal,
			r.LicenseeWinLoss	AS LicenseeWinLossOriginal,
			r.LicensingFee		AS LicensingFeeOriginal,
			r.LicenseeChargeRate		AS LicenseeChargeRateOriginal,
			PayToSupplier - WinPrizeAmount		AS PayToSupplierOriginal,
			(r.LicensingFee - (PayToSupplier - WinPrizeAmount)) AS CompanyIncomeOriginal
		FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate

		-- Grand Total
		SELECT * FROM @GrandTotal

	IF @BaseCurrencyName <> '' -- Group By Licensee
	BEGIN
		-- Total By Party
		;WITH cte_TempData AS
		(
		  SELECT r.PartyId, r.PartyName, r.ParentId,
			SUM(r.TotalTrans) TotalTrans,
			SUM(CAST(r.Turnover * e.Rate AS MONEY))			AS Turnover,
			SUM(CAST(r.WinPrizeAmount * e.Rate AS MONEY))	AS WinPrizeAmount,
			SUM(CAST(r.Contribution * e.Rate AS MONEY))		AS Contribution,
			SUM(CAST(r.JackpotPrize * e.Rate AS MONEY))		AS JackpotPrize,
			SUM(CAST(r.CustomerWinLoss * e.Rate AS MONEY))	AS CustomerWinLoss,
			SUM(CAST(LicenseeWinLoss * e.Rate AS MONEY))		AS LicenseeWinLoss,
			SUM(CAST(r.LicenseeChargeRate * e.Rate AS MONEY)) AS LicenseeChargeRate,
			SUM(CAST((r.PayToSupplier - WinPrizeAmount) * e.Rate AS MONEY)) AS PayToSupplier
			FROM #Result r 
			INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate
			GROUP BY r.PartyId, r.PartyName, r.ParentId
		), cte_TempResult AS
		(
			SELECT PartyId,PartyName,ParentId,TotalTrans,Turnover,WinPrizeAmount,Contribution,JackpotPrize,CustomerWinLoss,LicenseeWinLoss
				,CASE WHEN PartyID IN(25,30) THEN 0 
					  ELSE CASE WHEN LicenseeChargeRate > 0 THEN LicenseeChargeRate ELSE 0 END + Contribution - JackpotPrize - WinPrizeAmount 
				 END AS LicensingFee
				, CASE WHEN PartyID IN(25,30)
						THEN (SELECT TOP 1 SUM(CASE 
							WHEN r2.LicenseeWinLoss - r2.Contribution > MaxAmount THEN MaxAmount 
							WHEN r2.LicenseeWinLoss - r2.Contribution - MinAmount > 0 THEN r2.LicenseeWinLoss - r2.Contribution - MinAmount 
							WHEN r2.LicenseeWinLoss - r2.Contribution < 0 AND roc.RowIndex % @NumberOfTiers = 0 THEN r2.LicenseeWinLoss - r2.Contribution
							ELSE 0 END  * roc.Rate)
							FROM @RateOfCredit roc
							INNER JOIN cte_TempData r2 ON r2.PartyID = roc.PartyId
							WHERE r1.PartyID = r2.PartyID)
						ELSE  PayToSupplier
				  END AS PayToSupplier
			FROM cte_TempData r1
		)
		SELECT *, LicensingFee - PayToSupplier AS CompanyIncome
		FROM cte_TempResult

		-- Total By Party Group
		SELECT PartyId,TotalTrans,Turnover,WinPrizeAmount,Contribution,JackpotPrize,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,
			   LicensingFee - PayToSupplier AS CompanyIncome
		FROM @Total t
		WHERE Currency = @BaseCurrencyName
	END
	-- End Region
	
	DROP TABLE #Exchange
	DROP TABLE #Result
END
GO