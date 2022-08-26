/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_LaunchLicensee_InvoiceSettingIns]
	@PartyId				INT
	,@BillerId				INT
	,@InvoiceSettingData	VARCHAR(MAX)
	,@ErrCode				INT				= 0		OUTPUT
	,@ErrMsg				VARCHAR(4000)	= ''	OUTPUT
AS

/*
	Created: 20220623@Percy
	DB: DBCUST-bodb_Licensee
	Task: LA - Launch Licensee - Insert Invoice Setting

	Revisions:
		- 20220623@Percy: Initialize SP [RedmineID: #166504]
*/

BEGIN
	SET NOCOUNT ON

	-- Get invoice setting from input param
	DECLARE @InvoiceSetting TABLE (ProductId TINYINT, InvTypeId SMALLINT, InvTempId SMALLINT, BankId TINYINT, ActiveAddress TINYINT)

	BEGIN TRY
		DECLARE @InvoiceSettingXML XML = CONVERT(XML, @InvoiceSettingData)

		INSERT INTO @InvoiceSetting (ProductId, InvTypeId, InvTempId, BankId, ActiveAddress)
		SELECT
			t.c.value('@ProductId', 'TINYINT')		AS ProductId
			,t.c.value('@InvTypeId', 'SMALLINT')	AS InvTypeId
			,t.c.value('@InvTempId', 'SMALLINT')	AS InvTempId
			,t.c.value('@BankId', 'TINYINT')		AS BankId
			,t.c.value('@ActiveAddress', 'TINYINT') AS ActiveAddress
		FROM @InvoiceSettingXML.nodes('root/row') t(c)
		OPTION (OPTIMIZE FOR (@InvoiceSettingXML = NULL))
	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 101, @ErrMsg = 'Insert LA_InvoiceSetting failed. Please try again.'
		RETURN
	END CATCH

	-- Insert into LA_InvoiceSetting
	BEGIN TRY
		INSERT INTO dbo.LA_InvoiceSetting (FromPartyId, ToPartyId, ProductId, InvTypeId, InvTempId, BankId, ActiveAddress)
		SELECT @PartyId, @BillerId, ProductId, InvTypeId, InvTempId, BankId, ActiveAddress FROM @InvoiceSetting
	END TRY
	BEGIN CATCH
		SELECT @ErrCode = 102, @ErrMsg = 'Insert LA_InvoiceSetting failed. Please try again.'
		RETURN
	END CATCH
END
GO