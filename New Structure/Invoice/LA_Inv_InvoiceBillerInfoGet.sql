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
WITH RECOMPILE
AS
SET NOCOUNT ON
BEGIN
	DECLARE @InvoiceInfo AS TABLE(		
		InvoiceKey			VARCHAR(20), 
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
	
	DECLARE @InvoiceKey VARCHAR(20) = ''
	DECLARE @InvoiceNumber INT = 1						
	
	SELECT @InvoiceKey = i.InvoiceKey 
	FROM dbo.LA_InvoiceHeader i 
	WHERE i.BillerId = @BillerId
	
	SELECT @InvoiceNumber = ISNULL(MAX(i.InvoiceNo), 0) + 1
	FROM dbo.LA_InvoiceHeader i 
	WHERE i.BillerId = @BillerId
	
	UPDATE @InvoiceInfo
	SET InvoiceKey = @InvoiceKey,
	    InvoiceNumber = @InvoiceNumber

	SELECT TOP 1 ii.InvoiceKey, ii.InvoiceNumber, ii.InvoiceTemplateId, ii.InvoiceTemplateName, ii.InvoiceTempaltePath
	FROM @InvoiceInfo ii
END