USE bodb02
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceDetailInfoGet] 
	 @PartyId		INT,  
	 @FromDate		DATETIME,
	 @ToDate		DATETIME,  
	 @ProductCode	VARCHAR(6)
AS
/*	Header:
	Created: 2015.08.07 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb02
   
	Revisions: 
		+ 2015.08.07: Invoice Detail Info - Get
*/
/*	Example:
	USE bodb_licensee
	DECLARE @InvoiceHeaderId INT = 8
	
	EXEC LA_Inv_InvoiceDetailInfoGet @InvoiceHeaderId
*/
BEGIN
	SET NOCOUNT ON
	
	-- Region: Get base Currency
	DECLARE @BaseCurrencyId INT = 12
	DECLARE @BaseCurrencyName VARCHAR(5) = 'GBP'
	SET @BaseCurrencyId = ISNULL((	SELECT TOP 1 opd.CurrencyId
									FROM bodb_licensee.dbo.OAS_PartyDetail opd WITH(NOLOCK)	
									WHERE	opd.PartyID = @PartyId
								), 12)
	
	DECLARE @BaseCurrencyTable AS TABLE(Id INT, Name VARCHAR(5))
	INSERT	INTO @BaseCurrencyTable(Id,Name)
	EXECUTE bodb_Licensee.dbo.LA_SelBaseCurrency
	
	SELECT	@BaseCurrencyName = Name
	FROM	@BaseCurrencyTable bct
	WHERE	@BaseCurrencyId = bct.Id

	-- End Region	
	
	-- Region: Get party charge rate info	
	DECLARE @PartyChargeInfo AS TABLE (
		PartyId				INT
		, LicenseeId		INT
		, ProductID			INT
		, Rate				MONEY
		, FromDate			SMALLDATETIME
		, ToDate			SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyId, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)
		
	UPDATE @PartyChargeInfo
	SET    ToDate = '2015-07-15 00:00:00' -- SMALLDATETIME
	WHERE ProductID=0
	
	INSERT INTO @PartyChargeInfo(PartyId,LicenseeId,ProductID,Rate,FromDate,ToDate)
	VALUES
	(
	    14, -- PartyId - INT
	    4, -- LicenseeId - INT
	    0, -- ProductID - INT
	    0.2, -- Rate - MONEY
	    '2015-07-16 00:00', -- FromDate - SMALLDATETIME
	    '2015-07-31 00:00' -- ToDate - SMALLDATETIME
	)
	SELECT * FROM @PartyChargeInfo pci
	-- End Region
	
	-- Region: Call data from sp Settlement.
	CREATE	TABLE #tmpResult(
			Game				VARCHAR(100),
			WinLostDate			DATETIME,
			CurrencyId			INT,
			CurrencyName		NVARCHAR(20),
			Betcount			INT,
			Turnover			MONEY,
			MemberWinLoss		MONEY,
			MemberComm			MONEY,
			LicenseeWL			MONEY,
			LicenseeComm		MONEY,	
			Company				MONEY,
			TurnoverBase		MONEY,	
			MemberWinLossBase	MONEY,
			LicenseeWLBase		MONEY,
			CompanyBase			MONEY
	)
	
	--WHILE (SELECT COUNT(1) FROM @PartyChargeInfo pci
	
	INSERT INTO #tmpResult(Game,WinLostDate,CurrencyId,CurrencyName,Betcount,Turnover,MemberWinLoss,MemberComm,LicenseeWL,LicenseeComm,Company,TurnoverBase,MemberWinLossBase,LicenseeWLBase,CompanyBase)
	EXECUTE [dbo].[LA_Rpt_LicenseeSettlement] @PartyId, @FromDate, @ToDate, @ProductCode, @BaseCurrencyId, @BaseCurrencyName	
	
	SELECT * FROM #tmpResult r
	-- End region
	
	DROP TABLE #tmpResult
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceDetailInfoGet] TO bodbAdminNet