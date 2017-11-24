/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

USE bodb_licensee
GO

ALTER PROCEDURE dbo.LA_Rpt_CumulativeSBRebateSettlement
	@SettingGroupID		INT,
	@BaseCurrencyName	VARCHAR(10),
	@Environment		VARCHAR(20)
AS

/*
	Created: 20171030@Harper
	Description: Report to get data of the current cumulative SB rebate for user
	DB: DBLIC.bodb_licensee

	Revisions: 
		- 20171030@Harper: Create new SP Cumulative SB Rebate Settlement Report [#RedmineID: 84163]

	EXEC LA_Rpt_CumulativeSBRebateSettlement @SettingGroupID = 11, @BaseCurrencyName = 'EUR', @Environment = 'LOCAL'
*/

BEGIN
	
	CREATE TABLE #Result( CreatedDate	SMALLDATETIME
						, InvoiceType	VARCHAR(20)
						, InvoiceNo		INT
						, LicenseeName	VARCHAR(100)
						, [Description] NVARCHAR(200)
						, Amount		MONEY
						, Rebate		MONEY
						, Balance		MONEY
						, Remark		NVARCHAR(200)	
						)

	CREATE TABLE #tmpInvoiceList 	( InvoiceHeaderId INT, FromDate SMALLDATETIME, InvoiceDate SMALLDATETIME, InvoiceNumber INT, PartyId INT, Amount MONEY, Balance MONEY)	
	CREATE TABLE #tmpAssignment		( SettingGroupHeaderID INT, PartyID INT, FromDateOfParty SMALLDATETIME, ToDateOfParty SMALLDATETIME	)	
	CREATE TABLE #Exchange			( FirstExchangeDateByMonth SMALLDATETIME, LastExchangeDateByMonth SMALLDATETIME, ExchangeID INT, Rate FLOAT )
	
	DECLARE @tmpDiscountDetail TABLE ( SettingGroupHeaderID INT, TargetAmount MONEY, TargetAmountExchange MONEY, CurrencyId INT
										, CurrencyName VARCHAR(3), [Period] INT, Rate MONEY
										, FromDate SMALLDATETIME, ToDate SMALLDATETIME, RestartDate SMALLDATETIME)

	DECLARE @TotalValue MONEY, @Rate MONEY, @MaxDate SMALLDATETIME
			, @CumulativeInvDate SMALLDATETIME, @CutOffDate SMALLDATETIME, @FirstDayCurrMonth SMALLDATETIME, @FromDateOfGroupSetting SMALLDATETIME

	-- #Region: Get Cumulative Discount Group Setting

	INSERT INTO @tmpDiscountDetail( SettingGroupHeaderID, TargetAmount ,CurrencyId, CurrencyName ,Period ,Rate, FromDate, ToDate, RestartDate )	
	SELECT d.SettingGroupHeaderId, d.TargetAmount, 
			d.CurrencyId, e.Code, d.[Period], d.Rate, d.FromDate, d.ToDate, d.RestartDate
	FROM dbo.LA_SettingGroupDetail d WITH (NOLOCK)
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON d.CurrencyId = e.exchangeid
	WHERE d.SettingGroupHeaderId = @SettingGroupID AND d.[Status] = 'Active'

	IF (SELECT ToDate FROM @tmpDiscountDetail) < GETDATE()
		RETURN

	INSERT INTO #tmpAssignment( SettingGroupHeaderID, PartyID, FromDateOfParty, ToDateOfParty )	
	SELECT a.SettingGroupHeaderId, a.PartyId, a.FromDate, a.ToDate		
	FROM dbo.LA_SettingGroupAssignment a WITH (NOLOCK)
	WHERE a.SettingGroupHeaderId = @SettingGroupID

	-- #EndRegion: Get Cumulative Discount Group Setting

	-- #Region: Get Lasted Cumulative Invoice From Date

	SELECT @FirstDayCurrMonth = DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)

	SELECT @FromDateOfGroupSetting = FromDate FROM @tmpDiscountDetail

	SELECT @CumulativeInvDate = ISNULL(MAX(d.RestartDate), '1900-01-01')
	FROM @tmpDiscountDetail d	

	SELECT @CumulativeInvDate = CASE WHEN @CumulativeInvDate >= @FromDateOfGroupSetting 
									THEN @CumulativeInvDate 
									ELSE @FromDateOfGroupSetting 
								END

	SELECT @CutOffDate = DATEADD(MONTH, - (SELECT [Period] FROM @tmpDiscountDetail), @FirstDayCurrMonth)
	
	SELECT @MaxDate = MAX(fromdate)
	FROM 
	(
		VALUES(@CumulativeInvDate),(@FromDateOfGroupSetting), (@CutOffDate)--, ('2017-10-01') --comment for local testing
	) AS VALUE(fromdate)

	UPDATE t
	SET t.FromDateOfParty = CASE WHEN t.FromDateOfParty <= @MaxDate THEN @MaxDate ELSE t.FromDateOfParty END,
		t.ToDateOfParty = CASE WHEN t.ToDateOfParty > @FirstDayCurrMonth THEN @FirstDayCurrMonth ELSE t.ToDateOfParty END
	FROM #tmpAssignment t
	-- #EndRegion: Get Lasted Cumulative Invoice From Date  
	
	-- #Region: Get Exchange Rate	
	INSERT INTO #Exchange(FirstExchangeDateByMonth, LastExchangeDateByMonth, ExchangeID, Rate)
	SELECT FirstExchangeDateByMonth, LastExchangeDateByMonth, ExchangeID, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_SubExchangedailySel(@FromDateOfGroupSetting, @FirstDayCurrMonth, @BaseCurrencyName)
	-- #EndRegion: Get Exchange Rate
	
	-- #Region: Get SB Invoice Data
	INSERT INTO #tmpInvoiceList( InvoiceHeaderId ,FromDate, InvoiceDate ,InvoiceNumber ,PartyId ,Amount )	
	SELECT h.InvoiceHeaderId, h.FromDate, h.InvoiceDate, h.InvoiceNumber, h.PartyId
		, SUM(ISNULL(s.Income, 0) * e.Rate - ISNULL(s.Expense, 0) * e.Rate) AS Amount
	FROM dbo.LA_InvoiceStatement s WITH (NOLOCK)
		INNER JOIN dbo.LA_InvoiceHeader h WITH (NOLOCK) ON s.InvoiceHeaderId = h.InvoiceHeaderId
		INNER JOIN #tmpAssignment a ON h.PartyId = a.PartyID AND h.FromDate BETWEEN a.FromDateOfParty AND a.ToDateOfParty
		INNER JOIN #Exchange e ON h.CurrencyId = e.ExchangeID AND h.FromDate BETWEEN e.FirstExchangeDateByMonth AND e.LastExchangeDateByMonth
	WHERE s.InvItemTypeId IN (1, 4) AND s.ProductId = 0	AND h.StatusId = 0 -- active invoice
		AND (
				(
					( @Environment <> 'PRO' AND h.Environment = @Environment
						)
					OR 
					( @Environment = 'PRO' AND h.Environment = @Environment AND h.BillerId <> 221 -- Exclude Testing Biller for PRO
						)
				)
			)			  

	GROUP BY h.InvoiceHeaderId, h.FromDate, h.InvoiceDate, h.InvoiceNumber, h.PartyId

	; WITH balance AS (
						SELECT curr.Amount + COALESCE(SUM(prev.Amount),0) AS Balance, curr.InvoiceHeaderId
						FROM
						(
							SELECT SUM(Amount) Amount, InvoiceHeaderId
							FROM #tmpInvoiceList
							GROUP BY InvoiceHeaderId
						) curr
						LEFT OUTER JOIN
						(
							SELECT SUM(Amount) Amount, InvoiceHeaderId
							FROM #tmpInvoiceList
							GROUP BY InvoiceHeaderId
						) prev ON prev.InvoiceHeaderId < curr.InvoiceHeaderId
						GROUP BY curr.InvoiceHeaderId, curr.Amount
				)
	UPDATE d
	SET d.Balance = ISNULL(b.Balance , 0)
	FROM #tmpInvoiceList d
		INNER JOIN balance b ON d.InvoiceHeaderId = b.InvoiceHeaderId

	UPDATE @tmpDiscountDetail
	SET TargetAmountExchange = TargetAmount * e.Rate
	FROM @tmpDiscountDetail d
		INNER JOIN #Exchange e ON d.CurrencyId = e.ExchangeID AND (DATEADD(DAY, -1, @FirstDayCurrMonth)) BETWEEN FirstExchangeDateByMonth AND LastExchangeDateByMonth	

	INSERT INTO #Result
	        ( CreatedDate ,
	          InvoiceType ,
	          InvoiceNo ,
	          LicenseeName ,
	          [Description] ,
	          Amount ,	          
	          Balance 	          
	        )
	SELECT d.InvoiceDate, 'Invoice', d.InvoiceNumber, p.PartyName
			, 'Sportsbook fees for ' + CONVERT(NVARCHAR(3), DATENAME(MONTH, d.FromDate)) + ' ' + CAST(YEAR(d.FromDate) AS CHAR(4))
			, d.Amount, d.Balance
	FROM #tmpInvoiceList d
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON d.PartyId = p.PartyID

	SET @TotalValue = (SELECT TOP 1 Balance FROM #tmpInvoiceList ORDER BY InvoiceHeaderId DESC)
	SELECT @Rate = Rate FROM @tmpDiscountDetail
	
	IF (@TotalValue >= (SELECT TargetAmountExchange FROM @tmpDiscountDetail))
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
		          NULL , -- InvoiceNo - nvarchar(50)
		          '' , -- LicenseeName - varchar(100)
		          'Rebates on Sportsbook (' + CONVERT(VARCHAR(10), @Rate * 100) + '%) for ' 
					+ CONVERT(NVARCHAR(3), DATENAME(MONTH, @MaxDate)) + ' ' + CAST(YEAR(@MaxDate) AS CHAR(4)) 
					+ ' - ' + CONVERT(NVARCHAR(3), DATENAME(MONTH, DATEADD(DAY, -1, @FirstDayCurrMonth))) + ' ' + CAST(YEAR(DATEADD(DAY, -1, @FirstDayCurrMonth)) AS CHAR(4)),		         
		          @TotalValue * @Rate  -- Rebate - money		         
		        )
	END	
	-- #EndRegion: Get SB Invoice Data

	-- #Region: Return result
	;WITH licName AS (
						SELECT SS.SettingGroupHeaderID,
						STUFF(( SELECT ', ' + US.PartyName 
								FROM OAS_Party US
									INNER JOIN #tmpAssignment a ON us.PartyID = a.PartyID
								WHERE EXISTS (SELECT 1 FROM #tmpInvoiceList i WHERE a.PartyID = i.PartyId) 
									AND a.SettingGroupHeaderID = SS.SettingGroupHeaderID
								ORDER BY PartyName
								FOR XML PATH('')), 1, 1, '') [Licensees]
						FROM #tmpAssignment SS
						GROUP BY SS.SettingGroupHeaderID						
					)

	SELECT DATEADD(DAY, -1, @FirstDayCurrMonth) AS SettlementDate
		, l.Licensees AS LicenseeName
		, d.CurrencyName AS CurrencyName
		, d.Rate
		, d.Period
		, d.TargetAmount
	FROM @tmpDiscountDetail d
		INNER JOIN licName l ON l.SettingGroupHeaderID = d.SettingGroupHeaderID
	
	SELECT CreatedDate, InvoiceType, InvoiceNo, LicenseeName, [Description], Amount, Rebate, Balance
	FROM #Result	

	-- #EndRegion

	DROP TABLE #Exchange
	DROP TABLE #Result
	DROP TABLE #tmpAssignment
	DROP TABLE #tmpInvoiceList
END
GO