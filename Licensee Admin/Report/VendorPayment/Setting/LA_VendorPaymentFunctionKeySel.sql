/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE dbo.LA_VendorPaymentFunctionKeySel
AS
/*  
	Created: 20220324@Danny
	Task : Get all vendor products
	DB: DBLIC.bodb_Licensee
	
	Revisions:     
		- 20220324@Danny: Create SP [RedmineID: #168387]

*/
BEGIN
	SET NOCOUNT ON
	DECLARE @ParentID INT
	SELECT @ParentID = FunctionID FROM LA_Function WITH(NOLOCK)
	WHERE FunctionName = 'Vendor Payment Details'


	SELECT FunctionName, FunctionKey FROM LA_Function WITH(NOLOCK)
	WHERE ParentID = @ParentID

END
GO

