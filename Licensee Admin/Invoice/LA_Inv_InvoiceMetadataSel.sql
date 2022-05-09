/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].LA_Inv_InvoiceMetadataSel
	@InvoiceIdString VARCHAR(8000)
AS
/*	Header:
	Created: 2017.04.26 - Bruce
	Task : Get invoice header by id
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20170426@Bruce: Initialize SP
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT InvoiceHeaderId, InvoiceData, InvoicePath, Environment
	FROM dbo.LA_InvoiceHeader WITH (NOLOCK)
	WHERE InvoiceHeaderId IN(SELECT value FROM STRING_SPLIT(@InvoiceIdString, ','))
	
END
GO