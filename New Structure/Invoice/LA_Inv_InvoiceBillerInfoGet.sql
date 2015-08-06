USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Inv_InvoiceBillerInfoGet]   Script Date: 07/21/2015 09:12:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee
   
	Revisions: 
		+ 2015.08.06: Invoice Biller Info - Get
*/
/*	Example:
	USE bodb_licensee
	DECLARE @BillerId INT = 98
	DECLARE @PartyId INT = 14
	
	EXEC LA_Inv_InvoiceBillerInfoGet @BillerId, @PartyId
*/
ALTER PROCEDURE [dbo].[LA_Inv_InvoiceBillerInfoGet] 
	  @BillerId INT
	, @PayerId INT
AS
BEGIN
	SET NOCOUNT ON
	
	DECLARE @InvoiceInfo AS TABLE(		
		InvoiceSymbol		VARCHAR(20), 
		InvoiceNumber		INT,
		InvoiceTemplateId	SMALLINT,
		InvoiceTemplateName	VARCHAR(50),
		InvoiceTemplatePath	VARCHAR(255))
	INSERT INTO @InvoiceInfo(InvoiceTemplateId,InvoiceTemplateName,InvoiceTemplatePath)
	(
		SELECT ivs.InvTempId, itpl.InvTemplateName, itpl.TemplatePath
		FROM dbo.LA_InvoiceSetting ivs WITH(NOLOCK) INNER JOIN dbo.LA_InvoiceTemplate itpl WITH(NOLOCK) ON ivs.InvTempId = itpl.InvTemplateId
		WHERE ivs.FromPartyId = @PayerId 
			AND ivs.ToPartyId = @BillerId	
		GROUP BY ivs.InvTempId, itpl.InvTemplateName, itpl.TemplatePath
	)
	
	DECLARE @InvoiceSymbol VARCHAR(20) = ''
	DECLARE @InvoiceNumber INT = 1						
	
	SELECT TOP 1 @InvoiceSymbol = i.InvoiceSymbol 
	FROM dbo.LA_InvoiceHeader i WITH(NOLOCK)
	WHERE i.BillerId = @BillerId
	ORDER BY i.InvoiceDate DESC
	
	SELECT @InvoiceNumber = ISNULL(MAX(i.InvoiceNumber), 0) + 1
	FROM dbo.LA_InvoiceHeader i WITH(NOLOCK)
	WHERE i.BillerId = @BillerId
	
	UPDATE @InvoiceInfo
	SET InvoiceSymbol = @InvoiceSymbol,
	    InvoiceNumber = @InvoiceNumber

	SELECT TOP 1 ii.InvoiceSymbol, ii.InvoiceNumber, ii.InvoiceTemplateId, ii.InvoiceTemplateName, ii.InvoiceTemplatePath
	FROM @InvoiceInfo ii
	
	GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceBillerInfoGet] TO bodbAdminNet

END