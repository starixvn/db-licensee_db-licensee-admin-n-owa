USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceListGet] 
	@InvoiceNo		VARCHAR(50) = '',
	@InvoiceType	INT			= 0,
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
	DECLARE @InvoiceType	INT			= 0
	DECLARE @BillerId		INT			= 0
	DECLARE @PayerId		INT			= 0
	DECLARE @IssueFromDate	DATETIME	= '2015-7-1'
	DECLARE @IssueToDate	DATETIME	= '2015-7-31'
	
	EXEC [LA_Inv_InvoiceListGet] 
		@InvoiceNo,
		@InvoiceType,
		@BillerId,
		@PayerId,
		@IssueFromDate,
		@IssueToDate
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @BaseCurrencyTable AS TABLE(CurrencyId INT, CurrencyName VARCHAR(5))
	INSERT	INTO @BaseCurrencyTable(CurrencyId,CurrencyName)
	EXECUTE bodb_Licensee.dbo.LA_SelBaseCurrency
	
	SELECT  i.InvoiceHeaderId,
			i.BillerId,
			i.PartyId,
			i.RefNo,
			i.CurrencyId,
			bct.CurrencyName,
			i.InvoiceSymbol,
			i.InvoiceNumber,
			i.FromDate,
			i.ToDate,
			i.InvoiceDate,
			i.DueDate,
			i.Amount,
			i.InvoiceType,
			lis.InvTempId AS InvoiceTemplateId,
			lit.InvTemplateName AS InvoiceTemplateName,
			i.StatusId,
			i.Note,
			i.HasSent,
			i.CreatedBy,
			i.CreatedDateTime,
			i.UpdatedDateTime,
			i.IsSeparateProduct
	FROM	dbo.LA_InvoiceHeader i WITH(NOLOCK)
			INNER JOIN dbo.LA_InvoiceSetting lis ON i.BillerId = lis.ToPartyId AND i.PartyId = lis.FromPartyId AND i.InvoiceType = lis.InvTypeId
			INNER JOIN dbo.LA_InvoiceTemplate lit ON lis.InvTempId = lit.InvTemplateId
			INNER JOIN @BaseCurrencyTable bct ON i.CurrencyId = bct.CurrencyId
	WHERE	(i.InvoiceSymbol + CONVERT(VARCHAR(20), i.InvoiceNumber) = @InvoiceNo OR @InvoiceNo = '')
			AND (i.BillerId = @BillerId OR @BillerId = 0)
			AND (i.PartyId = @PayerId OR @PayerId = 0)
			AND (i.InvoiceType = @InvoiceType OR @InvoiceType = 0)
			AND i.ToDate BETWEEN @IssueFromDate AND @IssueToDate
	
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceListGet] TO bodbAdminNet