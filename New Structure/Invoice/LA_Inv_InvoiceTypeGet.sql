USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceTypeGet] 	
	  
AS
/*	Header:
	Created:2015.08.21 - Bravo.Tran
	Task :	Create Invoice 
	DB:		DB052.bodb_Licensee
   
	Revisions: 
		+ 2015.08.07: Invoice Type List - Get
*/
/*	Example:
	USE bodb_licensee
	EXEC [LA_Inv_InvoiceTypeGet]
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT i.InvTypeId, i.InvTypeName
	FROM dbo.LA_InvoiceType i
	
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceTypeGet] TO bodbAdminNet