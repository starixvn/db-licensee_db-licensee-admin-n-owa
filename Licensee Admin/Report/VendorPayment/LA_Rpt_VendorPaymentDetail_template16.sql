/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template16]
	@PartyIds			VARCHAR(4000)
	,@ProductID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(20)
	,@TimeZoneId		INT
	,@PlatformId		TINYINT = 0
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template5 - Template for PP, SG product, including some specific info such as: Promotion, Jackpot)
 * Revisions
	- 20210615@Danny: Initialize SP [#168387]
	- 20220927@Danny: Remove DBLink [#176986] 
	- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
	- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
 */
BEGIN
	SET NOCOUNT ON 
	DECLARE @ProductCode VARCHAR(50)
	SELECT @ProductCode = ProductPrefix FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @ProductID

	DECLARE @IsConvertNegativeFeeToZero BIT, @IsConvertNegativePaytoSupplierToZero BIT
	SELECT @IsConvertNegativeFeeToZero = IsConvertNegativeFeeToZero, @IsConvertNegativePaytoSupplierToZero = IsConvertNegativePaytoSupplierToZero  FROM dbo.LA_VendorPaymentSetting WITH(NOLOCK) WHERE ProductId = @ProductID

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	DECLARE		@Contribution INT,
				@JackpotPrize INT
	
	SELECT @Contribution = Bettype FROM LA_f_GroupBettype() WHERE TypeId = 2 AND ProductId = @ProductID
	SELECT @JackpotPrize = Bettype FROM LA_f_GroupBettype() WHERE TypeId = 3 AND ProductId = @ProductID

	DECLARE @BettypeIdList TABLE (BetTypeId INT)
	INSERT INTO @BettypeIdList (BetTypeId)
	SELECT	DISTINCT bettype
	FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,@ProductCode) la

	-- Region: Party List
	DECLARE @PartyList AS TABLE (PartyId INT, PartyName	VARCHAR(100), BranchName VARCHAR(100), ParentId	INT, ParentName VARCHAR(100), IsKeepNegativeAmount BIT DEFAULT 0)

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel

	UPDATE @PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0
	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM @PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId
	-- End region

	UPDATE p
	SET p.ParentName = pa.PartyName
	FROM @PartyList p
	INNER JOIN @PartyList pa ON pa.ParentId = 0 AND p.ParentId = pa.PartyId

	DECLARE @f_date3rd DATE = @FromDate
	DECLARE @t_date3rd DATE = @ToDate
	DECLARE @f_date DATE = DATEADD(DAY, -1, @FromDate)
	DECLARE @t_date DATE = DATEADD(DAY, 1, @ToDate)

	-- Region: Exchange
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(65),
		Rate			FLOAT
	)	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeID = 51 THEN 'INH' 
															WHEN ExchangeID = 92 THEN 'HID' 
															ELSE Code 
														END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End Region

	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(Id INT, Name VARCHAR(20), IsApply BIT)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

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

	BEGIN
		DECLARE @3rdRate AS TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
		INSERT INTO @3rdRate (PartyID, ProductID, DI_Rate, IsDeposit, Fromdate, Todate)
		SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate 
		FROM LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') r 
		INNER JOIN @PartyList p on p.ParentId = r.PartyID

		INSERT INTO @ChargeInfos (ChargeId, PartyId, LicenseeId, isDeposit, ProductID, Rate, Rate3rd, Fromdate, ToDate)
		SELECT DISTINCT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate
		FROM LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, @ProductCode) c
		INNER JOIN @3rdRate r ON r.PartyID = c.PartyID and r.ProductID = c.ProductID
		WHERE (c.DI_Rate = 0 AND c.isDeposit = 0) OR (c.DI_Rate > 0 and c.isDeposit = 1)
	END
	
	BEGIN
		CREATE TABLE #TempData (
			PartyID					INT,
			PartyName				NVARCHAR(100),
			ParentId				INT,
			ParentName				NVARCHAR(100),
			Winlostdate				DATETIME,
			CurrencyId				INT,
			Turnover				MONEY,
			TotalTrans				INT,
			CustomerWinLoss			MONEY,
			LicenseeWinloss			MONEY,
			LicensingFee			MONEY,
			PayToSupplier			MONEY,
			LicenseeContribution	MONEY,
			FullContribution		MONEY,
			JackpotPrize			MONEY,
			LicenseeChargeRate		MONEY,
			IsDeposit				BIT)

			-- Region: Calculate result
		CREATE TABLE #Result (
			PartyId			INT,
			PartyName		VARCHAR(100),
			ParentId		INT,
			ParentName		VARCHAR(100),
			WinLossDate		DATETIME,
			CurrencyId		INT,
			TotalTrans		INT,
			Turnover		MONEY,
			CustomerWinLoss	MONEY,
			LicenseeWinLoss	MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY,
			LicenseeContribution	MONEY,
			FullContribution	MONEY,
			JackpotPrize	MONEY,
			LicenseeChargeRate MONEY,
			IsDeposit		BIT,
			IsKeepNegativeAmount BIT
		)

		DECLARE @GrandTotal TABLE (
			CurrencyName	VARCHAR(20),
			TotalTrans		INT,
			Turnover		MONEY,
			CustomerWinLoss	MONEY,
			LicenseeWinLoss	MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY,
			CompanyIncome	MONEY,
			JackpotPrize	MONEY,
			LicenseeContribution	MONEY,
			FullContribution		MONEY
		)

		DECLARE @Total TABLE (
			PartyId			INT,
			TotalTrans		INT,
			Turnover		MONEY,
			CustomerWinLoss	MONEY,
			LicenseeWinLoss	MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY,
			CompanyIncome	MONEY,
			Currency		VARCHAR(20),
			JackpotPrize	MONEY,
			LicenseeContribution	MONEY,
			FullContribution		MONEY
		)
		IF @TimeZoneId = 1
		BEGIN
			;WITH cte_detail AS
			(
			SELECT
				b.RptDate as Winlostdate,
				b.CurrencyId,
				b.SiteId,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.Turnover END) AS Turnover,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.BetCount END) AS TotalTrans,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.Winloss END) AS CustomerWinLoss,
				- SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.Winloss END) AS LicenseeWinloss,
				SUM(CASE WHEN b.BetTypeId = @Contribution THEN -b.AWinloss ELSE 0 END) AS LicenseeContribution,
				SUM(CASE WHEN b.BetTypeId = @Contribution THEN ProgressiveContribution ELSE 0 END) AS FullContribution,
				SUM(CASE WHEN b.BetTypeId = @JackpotPrize THEN b.Winloss ELSE 0 END) AS JackpotPrize
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
				INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate BETWEEN ci.FromDate AND ci.ToDate
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
			WHERE b.RptDate BETWEEN @f_date3rd AND @t_date3rd
				AND b.RptDate3rd BETWEEN @f_date AND @t_date
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20
				AND b.BetTypeId IN (SELECT x.BetTypeId FROM @BettypeIdList x)
			GROUP BY b.RptDate, b.CurrencyId, b.SiteId
			)
			INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,LicenseeContribution,FullContribution,JackpotPrize,LicenseeChargeRate,IsDeposit)
			SELECT	ci.PartyID,
					b.Winlostdate,
					b.CurrencyId,
					SUM(Turnover),
					SUM(TotalTrans),
					SUM(CustomerWinLoss),
					SUM(LicenseeWinloss),
					SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate) + LicenseeContribution - JackpotPrize) AS LicensingFee,
					SUM((LicenseeWinloss - FullContribution) * ci.Rate3rd) AS PayToSupplier,
					SUM(LicenseeContribution),
					SUM(FullContribution),
					SUM(JackpotPrize),
					SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate)) AS LicenseeChargeRate,
					ci.IsDeposit
			FROM	cte_detail b
			INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
			GROUP BY b.Winlostdate, b.CurrencyId, ci.PartyID, ci.isDeposit
		END
		ELSE
		BEGIN
			;WITH cte_detail AS
			(
			SELECT
				b.RptDate3rd as Winlostdate,
				b.CurrencyId,
				b.SiteId,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.Turnover END) AS Turnover,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.BetCount END) AS TotalTrans,
				SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.Winloss END) AS CustomerWinLoss,
				- SUM(CASE WHEN b.BetTypeId IN (@Contribution,@JackpotPrize) THEN 0 ELSE b.Winloss END) AS LicenseeWinloss,
				SUM(CASE WHEN b.BetTypeId = @Contribution THEN -b.AWinloss ELSE 0 END) AS LicenseeContribution,
				SUM(CASE WHEN b.BetTypeId = @Contribution THEN ProgressiveContribution ELSE 0 END) AS FullContribution,
				SUM(CASE WHEN b.BetTypeId = @JackpotPrize THEN b.Winloss ELSE 0 END) AS JackpotPrize
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
				INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
			WHERE b.RptDate BETWEEN @f_date AND @t_date
				AND b.RptDate3rd BETWEEN @f_date3rd AND @t_date3rd
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20
				AND b.BetTypeId IN (SELECT x.BetTypeId FROM @BettypeIdList x)
			GROUP BY b.RptDate3rd, b.CurrencyId, b.SiteId
			)
			INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,LicenseeContribution,FullContribution,JackpotPrize,LicenseeChargeRate,IsDeposit)
			SELECT	ci.PartyID,
					b.Winlostdate,
					b.CurrencyId,
					SUM(Turnover),
					SUM(TotalTrans),
					SUM(CustomerWinLoss),
					SUM(LicenseeWinloss),
					SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate) + LicenseeContribution - JackpotPrize) AS LicensingFee,
					SUM((LicenseeWinloss - FullContribution) * ci.Rate3rd) AS PayToSupplier,
					SUM(LicenseeContribution),
					SUM(FullContribution),
					SUM(JackpotPrize),
					SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate)) AS LicenseeChargeRate,
					ci.IsDeposit
			FROM	cte_detail b
			INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
			GROUP BY b.Winlostdate, b.CurrencyId, ci.PartyID, ci.isDeposit
			-- End region
		END
	
	
		INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier,LicenseeContribution,FullContribution,JackpotPrize, LicenseeChargeRate,IsDeposit,IsKeepNegativeAmount)
		SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, 
		  CASE WHEN IsDeposit = 0 THEN 0 ELSE LicenseeChargeRate   + LicenseeContribution - JackpotPrize  END   AS LicensingFee, td.PayToSupplier, td.LicenseeContribution, td.FullContribution, td.JackpotPrize, td.LicenseeChargeRate,td.IsDeposit,p.IsKeepNegativeAmount
		FROM #TempData td
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId	
	

		WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
		BEGIN
			SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies)

			;WITH TotalByParty AS(
				SELECT CASE WHEN td.PartyId = 14 THEN 14 ELSE td.ParentId END ParentId, td.PartyId, td.IsDeposit, td.IsKeepNegativeAmount,
					SUM(td.TotalTrans) TotalTrans,
					SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
					SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
					SUM(td.LicenseeWinLoss * e.BaseCurrencyRate) LicenseeWinLoss,
					SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
					SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier,
					SUM(td.LicenseeContribution * e.BaseCurrencyRate) LicenseeContribution,
					SUM(td.FullContribution * e.BaseCurrencyRate) FullContribution,
					SUM(td.JackpotPrize * e.BaseCurrencyRate) JackpotPrize,
					SUM(td.LicenseeChargeRate * e.BaseCurrencyRate) LicenseeChargeRate
				FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
				ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
				GROUP BY CASE WHEN td.PartyId = 14 THEN 14 ELSE td.ParentId END, td.PartyId, td.IsDeposit, td.IsKeepNegativeAmount
			)
			INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome,JackpotPrize,LicenseeContribution,FullContribution)
			SELECT @tempCurrency, ParentId,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(CASE WHEN  IsDeposit = 0 THEN 0 
						 ELSE  CASE WHEN LicenseeChargeRate < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicenseeChargeRate END + LicenseeContribution - JackpotPrize END),
				SUM(CASE WHEN PayToSupplier <0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END),
				SUM(CASE WHEN  IsDeposit = 0 THEN 0 
						 ELSE  CASE WHEN LicenseeChargeRate < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicenseeChargeRate END + LicenseeContribution - JackpotPrize END - CASE WHEN PayToSupplier <0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END),
				SUM(JackpotPrize),
				SUM(LicenseeContribution),
				SUM(FullContribution)
			FROM TotalByParty
			GROUP BY ParentId
		
			INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome,JackpotPrize,LicenseeContribution,FullContribution)
			SELECT Currency,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(LicensingFee),
				SUM(PayToSupplier),
				SUM(LicensingFee - PayToSupplier),
				SUM(JackpotPrize),
				SUM(LicenseeContribution),
				SUM(FullContribution)
			FROM @Total
			WHERE Currency = @tempCurrency
			GROUP BY Currency

			DELETE @BaseCurrencies WHERE [Name] = @tempCurrency
		END
	
		-- Select data by Parties
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
			CAST((r.LicenseeWinLoss) AS MONEY) AS LicenseeWinLossOriginal,
			CAST((r.LicensingFee) AS MONEY) AS LicensingFeeOriginal,
			CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
			r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
			r.JackpotPrize AS JackpotPrizeOriginal,
			r.LicenseeContribution AS LicenseeContributionOriginal,
			r.FullContribution AS FullContributionOriginal,
			-- Select by base currency
			r.Turnover * e.Rate AS Turnover,
			CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
			CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
			CAST((r.LicensingFee * e.Rate) AS MONEY) AS LicensingFee,
			CAST((r.PayToSupplier * e.Rate)AS MONEY) AS PayToSupplier,
			CAST((r.LicensingFee - r.PayToSupplier) * e.Rate AS MONEY) AS CompanyIncome,
			CAST((r.JackpotPrize * e.Rate) AS MONEY) AS JackpotPrize,
			CAST((r.LicenseeContribution * e.Rate) AS MONEY) AS LicenseeContribution,
			CAST((r.FullContribution * e.Rate) AS MONEY) AS FullContribution
		FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate

		;WITH TotalByParty AS(
			SELECT td.ParentId, td.PartyId, td.IsDeposit, td.IsKeepNegativeAmount, td.PartyName,
				SUM(td.TotalTrans) TotalTrans,
				SUM(td.Turnover * e.Rate) Turnover,
				SUM(td.CustomerWinLoss * e.Rate) CustomerWinLoss,
				SUM(td.LicenseeWinLoss * e.Rate) LicenseeWinLoss,
				SUM(td.LicensingFee * e.Rate) LicensingFee,
				SUM(td.PayToSupplier * e.Rate) PayToSupplier,
				SUM(td.LicenseeContribution * e.Rate) LicenseeContribution,
				SUM(td.FullContribution * e.Rate) FullContribution,
				SUM(td.JackpotPrize * e.Rate) JackpotPrize,
				SUM(td.LicenseeChargeRate * e.Rate) LicenseeChargeRate
			FROM #Result td INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeId AND td.WinLossDate = e.ExchangeDate
			GROUP BY td.ParentId, td.PartyId, td.IsDeposit, td.IsKeepNegativeAmount, td.PartyName
		)
		SELECT CASE WHEN PartyId = 14 THEN 14 ELSE ParentId END ParentId,
			PartyId,
			PartyName,
			TotalTrans,
			Turnover,
			CustomerWinLoss,
			LicenseeWinLoss,
			CASE WHEN  IsDeposit = 0 THEN 0 ELSE CASE WHEN LicenseeChargeRate < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicenseeChargeRate END + LicenseeContribution - JackpotPrize END LicensingFee,
			CASE WHEN PayToSupplier <0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END PayToSupplier,
			CASE WHEN  IsDeposit = 0 THEN 0 ELSE  CASE WHEN LicenseeChargeRate < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicenseeChargeRate END + LicenseeContribution - JackpotPrize END - CASE WHEN PayToSupplier <0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END AS CompanyIncome,
			JackpotPrize,
			LicenseeContribution,
			FullContribution
		FROM TotalByParty
	
		-- Select Grand Total
		SELECT * FROM @GrandTotal
	
		-- Total
		SELECT 
			PartyId,
			TotalTrans,
			Turnover,
			CustomerWinLoss,
			LicenseeWinLoss,
			LicensingFee,
			PayToSupplier,
			CompanyIncome,
			JackpotPrize,
			LicenseeContribution,
			FullContribution
		FROM @Total t
		WHERE Currency = @BaseCurrencyName
	-- End Region

	END
	DROP TABLE #Exchange

END
