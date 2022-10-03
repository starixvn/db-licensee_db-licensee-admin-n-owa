/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template13]
	@PartyIds			VARCHAR(4000)
	,@ProductID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(20)
	,@GameType			TINYINT
	,@GroupBy			TINYINT
	,@PlatformId		TINYINT = 0
AS
/*
	Created by : [20220405@Danny]
	Task  : Vendor Payment Detail (template13 - MacauGame)
	Revisions
		- 20210615@Danny: Initialize SP [#168387]
		- 20220927@Danny: Remove DBLink [#176986]
		- 20221206@Malcolm: Separate data of Blueprint and Normal games for Macau Games product [RedmineId: #179006]
		- 20221003@Malcolm: Add platform filter [RedmineID: #165707]

	Param's Explanation:
		+ @GroupBy :
			- 0 : Licensee
			- 1 : GameType
			- 2 : Date 

		+ @GameType :
		  - 0 : all
		  - 1 : Blueprint
		  - 2 : NormalGame
 */

BEGIN
	SET NOCOUNT ON

	DECLARE @IsConvertNegativeFeeToZero BIT, @IsConvertNegativePaytoSupplierToZero BIT
	SELECT @IsConvertNegativeFeeToZero = IsConvertNegativeFeeToZero, @IsConvertNegativePaytoSupplierToZero = IsConvertNegativePaytoSupplierToZero  FROM dbo.LA_VendorPaymentSetting WITH(NOLOCK) WHERE ProductId = @ProductID

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = p.PartyName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	DECLARE @ProductCode VARCHAR(50)
	DECLARE @BettypeIdList TABLE (BetTypeId INT)
	
	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT, IsKeepNegativeAmount BIT DEFAULT 0)
	
	CREATE TABLE #ChargeRate (
		ChargeID		INT
		,PartyID		INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate			MONEY	DEFAULT 0
		,Rate3rd		MONEY	DEFAULT 0
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	)

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)

	CREATE TABLE #TempData (
		PartyID			INT,
		PartyName		NVARCHAR(100),
		ParentId		INT,
		ParentName		NVARCHAR(100),
		Winlostdate		DATETIME,
		CurrencyId		INT,
		Turnover		MONEY	DEFAULT 0,
		TotalTrans		INT		DEFAULT 0,
		CustomerWinLoss MONEY	DEFAULT 0,
		LicenseeWinloss MONEY	DEFAULT 0,
		LicensingFee	MONEY	DEFAULT 0,
		PayToSupplier	MONEY	DEFAULT 0,
		isDeposit		BIT,
		GameType		TINYINT
	)

	 -- Exchange
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, CASE WHEN ExchangeID = 51 THEN 'INH' 
										  WHEN ExchangeID = 92 THEN 'HID'  
										  ELSE Code END, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	-- ProductCode
	SELECT @ProductCode = ProductPrefix FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @ProductID

	-- Party list
	INSERT INTO #PartyList (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	UPDATE #PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0
	
	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM #PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId

	-- Bettype List
	INSERT INTO @BettypeIdList (BetTypeId)
	SELECT	DISTINCT bettype
	FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,@ProductCode) la

	-- Handle chargeRate
	BEGIN
		INSERT INTO #ChargeRate(ChargeId, PartyId, ProductID, LicenseeId, Rate, Fromdate, Todate, IsDeposit)
		(
			SELECT c.ChargeID, c.PartyID, c.ProductID, c.LicenseeID, 
				CASE WHEN ISNULL(c.IsDeposit,0)=0 THEN 0 ELSE c.DI_Rate END,
				c.Fromdate, c.Todate, ISNULL(c.IsDeposit,0)
			FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1) c		
		)		
	END

	-- Region: TempData 
	BEGIN
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,GameType,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee, PayToSupplier, isDeposit)
		SELECT	ci.PartyId,
				b.rptDate,
				b.CurrencyId,
				CASE WHEN bp.BetType IS NOT NULL THEN 1 ELSE 2 END AS GameType,
				SUM(b.Turnover) AS Turnover,
				SUM(b.BetCount) AS TotalTrans,
				SUM(b.WinLoss) AS CustomerWinLoss,
				- SUM(b.WinLoss) AS LicenseeWinloss,
				SUM(-b.WinLoss * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
				SUM(-b.WinLoss * 
				CASE 
					WHEN ci.IsDeposit = 1 THEN (CASE WHEN bp.Bettype IS NOT NULL THEN 0.045 ELSE 0.035 END)
					ELSE (CASE WHEN bp.Bettype IS NOT NULL THEN 0.03 ELSE 0.02 END)
				END) AS PayToSupplier,
				ci.isDeposit
		FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN bodb02.dbo.SportBettypeMatrix  bp WITH(NOLOCK) ON b.Bettype = bp.Bettype AND bp.ProductID = @ProductID AND bp.SubProduct = 'Blueprint'
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeID AND cr.CurrencyID = b.CurrencyId
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
			b.Status NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 AND b.CustomerCategory NOT IN (27,28)
			AND b.Bettype in (Select Bettype FROM LA_f_BettypeProductMapping(0,@ProductCode))
			AND (@GameType = 0 OR bp.Bettype IS NOT NULL AND @GameType = 1 OR bp.Bettype IS NULL AND @GameType = 2)
		GROUP BY b.rptDate, ci.PartyId, b.CurrencyId, ci.isDeposit, CASE WHEN bp.BetType IS NOT NULL THEN 1 ELSE 2 END 

	END
	-- Region: Calculate result
	CREATE TABLE #Result (
		PartyId			INT,
		PartyName		VARCHAR(100),
		ParentId		INT,
		ParentName		VARCHAR(100),
		WinLossDate		DATETIME,
		CurrencyId		INT,
		GameType		TINYINT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		IsKeepNegativeAmount BIT	
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, GameType, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, IsKeepNegativeAmount)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.GameType, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee, td.PayToSupplier, p.IsKeepNegativeAmount
	FROM #TempData td
		INNER JOIN #PartyList p ON td.PartyId = p.PartyID
		INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId	

	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
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
		Name VARCHAR(20)
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC bodb_licensee.dbo.LA_SelBaseCurrency

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	
	BEGIN
		WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
		BEGIN
			SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies)

			;WITH TotalByParty AS(
				SELECT  CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END ParentId, 
						td.PartyId, 
						td.IsKeepNegativeAmount,
						SUM(td.TotalTrans) TotalTrans,
						SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
						SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
						SUM(td.LicenseeWinLoss * e.BaseCurrencyRate) LicenseeWinLoss,
						SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
						SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier
				FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
				ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
				GROUP BY CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END, td.PartyId, td.IsKeepNegativeAmount
			)
			INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome)
			SELECT @tempCurrency,ParentId,
				TotalTrans,
				Turnover,
				CustomerWinLoss,
				LicenseeWinLoss,
				CASE WHEN LicensingFee < 0 AND  @IsConvertNegativeFeeToZero = 1 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END,
				CASE WHEN PayToSupplier < 0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END,
				CASE WHEN LicensingFee < 0 AND @IsConvertNegativeFeeToZero = 1 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END - CASE WHEN PayToSupplier < 0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END
			FROM TotalByParty

			INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier, CompanyIncome)
			SELECT Currency,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(LicensingFee),
				SUM(PayToSupplier),
				SUM(LicensingFee - PayToSupplier)
			FROM @Total
			WHERE Currency = @tempCurrency
			GROUP BY Currency

			DELETE @BaseCurrencies WHERE [Name] = @tempCurrency
		END
		-- Select data by Parties

		DECLARE @result TABLE 
		(
			PartyId						INT
			,PartyName					VARCHAR(100)
			,ParentId					INT
			,ParentName					VARCHAR(100)
			,WinLossDate				DATETIME
			,CurrencyName				VARCHAR(10)
			,GameType					INT
			,TotalTrans					INT
			,TurnoverOriginal			MONEY
			,CustomerWinLossOriginal	MONEY
			,LicenseeWinLossOriginal	MONEY
			,LicensingFeeOriginal		MONEY
			,PayToSupplierOriginal		MONEY
			,CompanyIncomeOriginal		MONEY
			,Turnover					MONEY
			,CustomerWinLoss			MONEY
			,LicenseeWinLoss			MONEY
			,LicensingFee				MONEY
			,PayToSupplier				MONEY
			,CompanyIncome				MONEY
		)

		INSERT INTO @result 
		(
			PartyId						
			,PartyName					
			,ParentId					
			,ParentName					
			,WinLossDate				
			,CurrencyName				
			,GameType					
			,TotalTrans					
			,TurnoverOriginal			
			,CustomerWinLossOriginal	
			,LicenseeWinLossOriginal	
			,LicensingFeeOriginal		
			,PayToSupplierOriginal		
			,CompanyIncomeOriginal		
			,Turnover					
			,CustomerWinLoss			
			,LicenseeWinLoss			
			,LicensingFee				
			,PayToSupplier				
			,CompanyIncome				
		)
		SELECT 
			r.PartyId,
			r.PartyName,
			CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId,
			CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE r.ParentName END ParentName,
			r.WinLossDate,
			e.CurrencyCode AS CurrencyName,
			CASE WHEN @GroupBy = 1 THEN r.GameType ELSE 0 END AS GameType,
			-- Select by origin currency
			SUM(r.TotalTrans) AS TotalTrans,
			SUM(r.Turnover) AS TurnoverOriginal,
			SUM(r.CustomerWinLoss) AS CustomerWinLossOriginal,
			SUM(r.LicenseeWinLoss) AS LicenseeWinLossOriginal,
			SUM(r.LicensingFee) AS LicensingFeeOriginal,
			SUM(r.PayToSupplier) AS PayToSupplierOriginal,
			SUM(r.LicensingFee - r.PayToSupplier) AS CompanyIncomeOriginal,
			-- Select by base currency
			SUM(r.Turnover * e.Rate) AS Turnover,
			SUM(r.CustomerWinLoss * e.Rate) AS CustomerWinLoss,
			SUM(r.LicenseeWinLoss * e.Rate) AS LicenseeWinLoss,
			SUM(r.LicensingFee * e.Rate) AS LicensingFee,
			SUM(r.PayToSupplier * e.Rate) AS PayToSupplier,
			SUM((r.LicensingFee - r.PayToSupplier) * e.Rate)  AS CompanyIncome
		FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate
		GROUP BY 
			r.PartyId,
			r.PartyName,
			CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END,
			CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE r.ParentName END,
			r.WinLossDate,
			e.CurrencyCode,
			CASE WHEN @GroupBy = 1 THEN r.GameType ELSE 0 END 

		SELECT 
			PartyId						
			,PartyName					
			,ParentId					
			,ParentName					
			,CASE WHEN @GroupBy = 1 THEN @ToDate ELSE WinLossDate END AS WinLossDate				
			,CASE WHEN @GroupBy = 1 THEN '' ELSE CurrencyName END AS CurrencyName				
			,CASE WHEN @GroupBy = 1 THEN GameType ELSE 0 END AS GameType	
			,CASE CASE WHEN @GroupBy = 1 THEN GameType ELSE 0 END 
				WHEN 0 THEN 'Total'
				WHEN 1 THEN 'Blueprint'
				WHEN 2 THEN 'Normal Games'
			END AS GameTypeName										
			,SUM(TotalTrans) AS	TotalTrans			
			,SUM(TurnoverOriginal) AS TurnoverOriginal		
			,SUM(CustomerWinLossOriginal) AS CustomerWinLossOriginal	
			,SUM(LicenseeWinLossOriginal) AS LicenseeWinLossOriginal	
			,SUM(LicensingFeeOriginal) AS LicensingFeeOriginal		
			,SUM(PayToSupplierOriginal) AS PayToSupplierOriginal	
			,SUM(CompanyIncomeOriginal) AS CompanyIncomeOriginal	
			,SUM(Turnover) AS Turnover				
			,SUM(CustomerWinLoss) AS CustomerWinLoss			
			,SUM(LicenseeWinLoss) AS LicenseeWinLoss			
			,SUM(LicensingFee) AS LicensingFee			
			,SUM(PayToSupplier) AS PayToSupplier			
			,SUM(CompanyIncome) AS CompanyIncome	
		FROM @result
		GROUP BY PartyId, PartyName, ParentId, ParentName		
			,CASE WHEN @GroupBy = 1 THEN @ToDate ELSE WinLossDate END
			,CASE WHEN @GroupBy = 1 THEN '' ELSE CurrencyName END
			,CASE WHEN @GroupBy = 1 THEN GameType ELSE 0 END		
		ORDER BY PartyId, PartyName, ParentId, ParentName
			,CASE WHEN @GroupBy = 1 THEN @ToDate ELSE WinLossDate END
			,CASE WHEN @GroupBy = 1 THEN '' ELSE CurrencyName END
			,CASE WHEN @GroupBy = 1 THEN GameType ELSE 0 END	

		;WITH totalByParty AS
		(
		SELECT r.PartyId, r.PartyName, r.ParentId,
			SUM(r.TotalTrans) AS TotalTrans,
			SUM(r.Turnover * e.Rate) Turnover,
			SUM(r.CustomerWinLoss * e.Rate) CustomerWinLoss,
			SUM(r.LicenseeWinLoss * e.Rate) LicenseeWinLoss,
			SUM(r.LicensingFee * e.Rate) LicensingFee,
			SUM(r.PayToSupplier * e.Rate) PayToSupplier,
			r.IsKeepNegativeAmount
		FROM #Result r
			INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLossDate = e.ExchangeDate
		GROUP BY r.PartyId, r.PartyName, r.ParentId, r.IsKeepNegativeAmount
		)
		SELECT	PartyId, 
				PartyName, 
				CASE WHEN PartyId = 14 THEN 14 ELSE ParentId END ParentId, 
				TotalTrans, 
				Turnover, 
				CustomerWinLoss, 
				LicenseeWinLoss, 
				CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicensingFee END LicensingFee, 
				CASE WHEN PayToSupplier <0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END PayToSupplier, 
				CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicensingFee END - CASE WHEN PayToSupplier <0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END AS CompanyIncome
		FROM totalByParty
	
		-- Select Grand Total
		SELECT 	CurrencyName,
				TotalTrans		,
				Turnover		,
				CustomerWinLoss	,
				LicenseeWinLoss	,
				LicensingFee	,
				PayToSupplier	,
				CompanyIncome	 
		FROM @GrandTotal
	
		-- Total
		SELECT 
			PartyId
			,GameType
			,CASE GameType WHEN 1 THEN 'Blueprint'
			               WHEN 2 THEN 'Normal Games' 
						   WHEN 0 THEN 'Total'
			 END AS GameTypeName
			,SUM(TotalTrans) AS TotalTrans
			,SUM(Turnover) AS Turnover
			,SUM(CustomerWinLoss) AS CustomerWinLoss
			,SUM(LicenseeWinLoss) AS LicenseeWinLoss
			,SUM(LicensingFee) AS LicensingFee
			,SUM(PayToSupplier) AS PayToSupplier
			,SUM(CompanyIncome) AS CompanyIncome
		FROM (
			SELECT ParentId AS PartyId, GameType, TotalTrans, Turnover, CustomerWinLoss,LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome
			FROM @result t
			WHERE @GroupBy = 1
			UNION ALL
			SELECT PartyId, 0 AS GameType, TotalTrans,Turnover, CustomerWinLoss,LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome
			FROM @Total t
			WHERE Currency = @BaseCurrencyName 
		) AS r
		GROUP BY PartyId, GameType
		ORDER BY PartyId, CASE WHEN r.GameType = 0 THEN 1000 ELSE r.GameType END ASC
	-- End Region
	END


	DROP TABLE	#PartyList
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
	DROP TABLE  #TempData	
	DROP TABLE  #Result
END
