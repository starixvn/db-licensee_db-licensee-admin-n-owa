/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceTypeGet] 	
AS
/*	Header:
	Created:2015.08.21 - Bravo.Tran
	Task :	Create Invoice 
	DB:		DBCUST.bodb_Licensee
   
	Revisions: 
		- 20150807@Bravo: Invoice Type List - Get
*/
/*	Example:
	USE bodb_licensee
	EXEC [LA_Inv_InvoiceTypeGet]
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT i.InvTypeId, i.InvTypeName
	FROM dbo.LA_InvoiceType i WITH (NOLOCK)
END
GO