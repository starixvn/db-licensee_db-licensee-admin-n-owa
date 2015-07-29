USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Inv_InvoiceBillerInfoGet]   Script Date: 07/21/2015 09:12:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceBillerInfoGet] 
	  @BillerId INT
	, @PayerId INT
AS
SET NOCOUNT ON
BEGIN
	DECLARE @InvoiceInfo AS TABLE(		
		InvoiceSymbol		VARCHAR(20), 
		InvoiceNumber		INT,
		InvoiceTemplateId	SMALLINT,
		InvoiceTemplateName	VARCHAR(50),
		InvoiceTempaltePath	VARCHAR(255))
	INSERT INTO @InvoiceInfo(InvoiceTemplateId,InvoiceTemplateName,InvoiceTempaltePath)
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

	SELECT TOP 1 ii.InvoiceSymbol, ii.InvoiceNumber, ii.InvoiceTemplateId, ii.InvoiceTemplateName, ii.InvoiceTempaltePath
	FROM @InvoiceInfo ii
END