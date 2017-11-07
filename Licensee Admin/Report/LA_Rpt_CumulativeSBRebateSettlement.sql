USE bodb_licensee
GO

ALTER PROCEDURE dbo.LA_Rpt_CumulativeSBRebateSettlement
	@SettingGroupID		INT,
	@BaseCurrencyName	VARCHAR(10)
AS

/*
	Created: 20171030@Harper
	Description: Report to get data of the current cumulative SB rebate for user
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20171030@Harper: Create new SP Cumulative SB Rebate Settlement Report [#RedmineID: 84163]

	EXEC LA_Rpt_CumulativeSBRebateSettlement @SettingGroupID = 1, @BaseCurrencyName = 'EUR'
*/

BEGIN
	
	CREATE TABLE #Result( CreatedDate	SMALLDATETIME
						, InvoiceType	VARCHAR(20)
						, InvoiceNo		NVARCHAR(50)
						, LicenseeName	VARCHAR(100)
						, [Description] NVARCHAR(200)
						, Amount		MONEY
						, Rebate		MONEY
						, Balance		MONEY
						, Remark		NVARCHAR(200)	
						)

	CREATE TABLE #tmpDetail			( InvoiceHeaderId INT, FromDate SMALLDATETIME, InvoiceNumber NVARCHAR(50), PartyId INT, Amount MONEY, Balance MONEY)	
	CREATE TABLE #tmpAssignment		( PartyID INT, FromDate	SMALLDATETIME, ToDate SMALLDATETIME	)	
	CREATE TABLE #Exchange			( FirstExchangeDateByMonth SMALLDATETIME, LastExchangeDateByMonth SMALLDATETIME, ExchangeID INT, Rate FLOAT )
	CREATE TABLE #tmpDiscountDetail ( SettingGroupHeaderID INT, TargetAmount MONEY, TargetAmountExchange MONEY, CurrencyId INT, CurrencyName VARCHAR(3), [Period] INT, Rate MONEY, FromDate SMALLDATETIME, ToDate SMALLDATETIME)

	DECLARE @TotalValue MONEY, @Rate FLOAT
			, @CumulativeInvDate SMALLDATETIME, @CutOffDate SMALLDATETIME, @FirstDayCurrMonth SMALLDATETIME, @FromDate SMALLDATETIME

	-- #Region: Get Cumulative Discount Group Setting

	INSERT INTO #tmpDiscountDetail( SettingGroupHeaderID, TargetAmount ,CurrencyId, CurrencyName ,Period ,Rate, FromDate, ToDate )	
	SELECT d.SettingGroupHeaderId, d.TargetAmount, d.CurrencyId, e.Code, d.[Period], d.Rate, d.FromDate, d.ToDate
	FROM dbo.LA_SettingGroupDetail d WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON d.CurrencyId = e.exchangeid
	WHERE d.SettingGroupHeaderId = @SettingGroupID AND d.[Status] = 'Active'

	IF (SELECT ToDate FROM #tmpDiscountDetail) < GETDATE()
		RETURN

	INSERT INTO #tmpAssignment( PartyID, FromDate, ToDate )	
	SELECT a.PartyId, a.FromDate, a.ToDate		
	FROM dbo.LA_SettingGroupAssignment a WITH (NOLOCK)
	WHERE a.SettingGroupHeaderId = @SettingGroupID

	-- #EndRegion: Get Cumulative Discount Group Setting

	-- #Region: Get Lasted Cumulative Invoice From Date

	SELECT @FirstDayCurrMonth = DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)
	SELECT @FromDate = FromDate FROM #tmpDiscountDetail

	SELECT @CumulativeInvDate = MAX(a.FromDate)
	FROM dbo.LA_InvoiceHeader h WITH (NOLOCK)
		INNER JOIN #tmpAssignment a ON h.PartyId = a.PartyID
	WHERE h.InvoiceType = 11

	SELECT @CumulativeInvDate = CASE WHEN @CumulativeInvDate IS NULL 
									THEN DATEADD(MONTH, - (SELECT [Period] FROM #tmpDiscountDetail), @FirstDayCurrMonth)
									ELSE @CumulativeInvDate 
								END

	SELECT @CutOffDate = CASE WHEN @CumulativeInvDate <= @FromDate 
							THEN @FromDate
							ELSE @CumulativeInvDate
						END	

	SELECT @CutOffDate = CASE WHEN @CutOffDate <= '2017-10-01' 
							THEN '2017-10-01' 
							ELSE @CutOffDate 
						END

	UPDATE t
	SET FromDate = CASE WHEN FromDate <= @CutOffDate THEN @CutOffDate ELSE FromDate END,
		ToDate = CASE WHEN ToDate > @FirstDayCurrMonth THEN @FirstDayCurrMonth ELSE ToDate END
	FROM #tmpAssignment t

	-- #EndRegion: Get Lasted Cumulative Invoice From Date  

	-- #Region: Get Exchange Rate

	INSERT INTO #Exchange(FirstExchangeDateByMonth, LastExchangeDateByMonth, ExchangeID, Rate)
	SELECT FirstExchangeDateByMonth, LastExchangeDateByMonth, ExchangeID, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_SubExchangedailySel(@CutOffDate, @FirstDayCurrMonth, @BaseCurrencyName)

	-- #EndRegion: Get Exchange Rate

	-- #Region: Get SB Invoice Data
	INSERT INTO #tmpDetail( InvoiceHeaderId ,FromDate ,InvoiceNumber ,PartyId ,Amount )	
	SELECT h.InvoiceHeaderId, h.FromDate, h.OfficialInvoiceNo, h.PartyId
		, SUM(ISNULL(s.Income, 0) * e.Rate - ISNULL(s.Expense, 0) * e.Rate) AS Amount
	FROM dbo.LA_InvoiceStatement s WITH (NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH (NOLOCK) ON s.InvoiceHeaderId = h.InvoiceHeaderId
		INNER JOIN #tmpAssignment a ON h.PartyId = a.PartyID AND h.FromDate BETWEEN a.FromDate AND a.ToDate
		INNER JOIN #Exchange e ON h.CurrencyId = e.ExchangeID AND h.FromDate BETWEEN e.FirstExchangeDateByMonth AND e.LastExchangeDateByMonth
	WHERE s.InvItemTypeId IN (1, 4) AND s.ProductId = 0		
	GROUP BY h.InvoiceHeaderId, h.FromDate, h.OfficialInvoiceNo, h.PartyId

	; WITH balance AS (
						SELECT curr.Amount + COALESCE(SUM(prev.Amount),0) AS Balance, curr.InvoiceHeaderId
						FROM
						(
							SELECT SUM(Amount) Amount, InvoiceHeaderId
							FROM #tmpDetail
							GROUP BY InvoiceHeaderId
						) curr
						LEFT OUTER JOIN
						(
							SELECT SUM(Amount) Amount, InvoiceHeaderId
							FROM #tmpDetail
							GROUP BY InvoiceHeaderId
						) prev ON prev.InvoiceHeaderId < curr.InvoiceHeaderId
						GROUP BY curr.InvoiceHeaderId, curr.Amount
				)
	UPDATE d
	SET d.Balance = ISNULL(b.Balance , 0)
	FROM #tmpDetail d
		INNER JOIN balance b ON d.InvoiceHeaderId = b.InvoiceHeaderId

	UPDATE #tmpDiscountDetail
	SET TargetAmountExchange = TargetAmount * e.Rate
	FROM #tmpDiscountDetail d
		INNER JOIN #Exchange e ON d.CurrencyId = e.ExchangeID AND d.FromDate BETWEEN FirstExchangeDateByMonth AND LastExchangeDateByMonth
	
	INSERT INTO #Result
	        ( CreatedDate ,
	          InvoiceType ,
	          InvoiceNo ,
	          LicenseeName ,
	          [Description] ,
	          Amount ,	          
	          Balance 	          
	        )
	SELECT d.FromDate, 'Invoice', d.InvoiceNumber, p.PartyName
			, 'Sportsbook fees for ' + CONVERT(NVARCHAR(3), DATENAME(MONTH, d.FromDate)) + ' ' + CAST(YEAR(d.FromDate) AS CHAR(4))
			, d.Amount, d.Balance
	FROM #tmpDetail d
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON d.PartyId = p.PartyID

	SET @TotalValue = (SELECT TOP 1 Balance FROM #tmpDetail ORDER BY InvoiceHeaderId DESC)
	SELECT @Rate = Rate FROM #tmpDiscountDetail

	IF (@TotalValue >= (SELECT TargetAmountExchange FROM #tmpDiscountDetail))
	BEGIN
		INSERT INTO #Result
		        ( CreatedDate ,
		          InvoiceType ,
		          InvoiceNo ,
		          LicenseeName ,
		          [Description] ,		          
		          Rebate 	    
		        )
		VALUES  ( DATEADD(DAY, -1, @FirstDayCurrMonth) , -- CreatedDate - smalldatetime
		          'Rebate' , -- InvoiceType - varchar(20)
		          N'' , -- InvoiceNo - nvarchar(50)
		          '' , -- LicenseeName - varchar(100)
		          'Rebates on Sportsbook (' + CONVERT(VARCHAR(3), @Rate * 100) + '%) ' 
					+ CONVERT(NVARCHAR(3), DATENAME(MONTH, @CutOffDate)) + ' ' + CAST(YEAR(@CutOffDate) AS CHAR(4)) 
					+ ' - ' + CONVERT(NVARCHAR(3), DATENAME(MONTH, DATEADD(DAY, -1, @FirstDayCurrMonth))) + ' ' + CAST(YEAR(DATEADD(DAY, -1, @FirstDayCurrMonth)) AS CHAR(4)),		         
		          @TotalValue * @Rate  -- Rebate - money		         
		        )
	END	
	-- #EndRegion: Get SB Invoice Data

	-- #Region: Return result
	
	SELECT DATEADD(DAY, -1, @FirstDayCurrMonth) AS SettlementDate
		, h.GroupName AS LicenseeName
		, d.CurrencyName
		, d.Rate
		, d.Period
		, d.TargetAmount
	FROM dbo.LA_SettingGroupHeader h WITH (NOLOCK)
		INNER JOIN #tmpDiscountDetail d ON h.SettingGroupHeaderId = d.SettingGroupHeaderID	

	SELECT CreatedDate, InvoiceType, InvoiceNo, LicenseeName, [Description], Amount, Rebate, Balance
	FROM #Result

	-- #EndRegion

	DROP TABLE #Exchange
	DROP TABLE #Result
	DROP TABLE #tmpAssignment
	DROP TABLE #tmpDetail
	DROP TABLE #tmpDiscountDetail
END
GO



