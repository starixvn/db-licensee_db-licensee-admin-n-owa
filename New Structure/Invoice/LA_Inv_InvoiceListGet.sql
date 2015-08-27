USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceListGet] 
	@InvoiceNo		VARCHAR(50) = '',
	@InvoiceTypes	VARCHAR(100)= '',
	@BillerId		INT			= 0,
	@PayerId		INT			= 0,
	@IssueFromDate	DATETIME,
	@IssueToDate	DATETIME
	  
AS
/*	Header:
	Created:2015.08.21 - Bravo.Tran
	Task :	Create Invoice 
	DB:		DB052.bodb_Licensee
   
	Revisions: 
		+ 2015.08.07: Invoice Info List - Get
*/
/*	Example:
	USE bodb_licensee
	DECLARE @InvoiceNo		VARCHAR(50)	= ''
	DECLARE @InvoiceTypes	VARCHAR(100)= '1,2,3'
	DECLARE @BillerId		INT			= 0
	DECLARE @PayerId		INT			= 0
	DECLARE @IssueFromDate	DATETIME	= '2015-7-1'
	DECLARE @IssueToDate	DATETIME	= '2015-7-31'
	
	EXEC [LA_Inv_InvoiceListGet] @InvoiceNo,@InvoiceTypes,@BillerId,@PayerId,@IssueFromDate,@IssueToDate
*/
BEGIN
	SET NOCOUNT ON
	-- Region: Get Invoice Type ID
	DECLARE @InvoiceTypeTable TABLE (Id INT NOT NULL)	
	DECLARE @Delimiter CHAR(1)=','

	;WITH SEPARATEDTABLE (STARTVAL, STOPVAL) 
	AS 
	(
		SELECT
			STARTVAL = CAST(1 AS INT),
			STOPVAL = CHARINDEX(@Delimiter, @InvoiceTypes + @Delimiter) 
		UNION ALL SELECT
			STARTVAL = STOPVAL + 1,
			STOPVAL = CHARINDEX(@Delimiter, @InvoiceTypes + @Delimiter, STOPVAL + 1)
		FROM SEPARATEDTABLE
		WHERE STOPVAL > 0
	)
	INSERT @InvoiceTypeTable (Id)
	SELECT LTRIM(RTRIM(SUBSTRING(@InvoiceTypes, STARTVAL,	CASE
																WHEN STOPVAL > 0 THEN STOPVAL - STARTVAL
																ELSE 0
															END)))
	FROM SEPARATEDTABLE
	WHERE STOPVAL > 0
	OPTION (MAXRECURSION 0)
	-- End Region
	
	-- Region: Base currency
	DECLARE @BaseCurrencyTable AS TABLE(CurrencyId INT, CurrencyName VARCHAR(5))
	INSERT	INTO @BaseCurrencyTable(CurrencyId,CurrencyName)
	EXECUTE bodb_Licensee.dbo.LA_SelBaseCurrency
	-- End Region
	
	-- Region: Get data
	SELECT  i.InvoiceHeaderId,						
			i.InvoiceSymbol,
			i.InvoiceNumber,			
			b.BillerName,
			p.PartyName AS PayerName,						
			it.InvTypeName AS InvoiceTypeName,
			i.DueDate,
			i.ToDate,
			bct.CurrencyName,
			i.Amount
			
	FROM	dbo.LA_InvoiceHeader i WITH(NOLOCK)
			INNER JOIN dbo.LA_BillerInfo b ON i.BillerId = b.PartyId
			INNER JOIN dbo.OAS_Party p ON i.PartyId = p.PartyID
			INNER JOIN dbo.LA_InvoiceType it ON i.InvoiceType = it.InvTypeId
			INNER JOIN @BaseCurrencyTable bct ON i.CurrencyId = bct.CurrencyId
	WHERE	(i.InvoiceSymbol + CONVERT(VARCHAR(20), i.InvoiceNumber) = @InvoiceNo OR @InvoiceNo = '')
			AND (i.BillerId = @BillerId OR @BillerId = 0)
			AND (i.PartyId = @PayerId OR @PayerId = 0)
			AND i.InvoiceType IN (SELECT Id FROM @InvoiceTypeTable)
			AND i.ToDate BETWEEN @IssueFromDate AND @IssueToDate
	
	-- End Region
	
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceListGet] TO bodbAdminNet

