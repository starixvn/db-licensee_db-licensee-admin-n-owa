/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeIns_RollBack]
	@GroupMinFeeId SMALLINT
AS
/*
	Created: 20200630@Happy
	Task : Insert new GroupMinFee
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20200630@Happy: Implement Group Min Fee [#134492]

	Param's Explannation: 
*/
BEGIN
	SET NOCOUNT ON;
	
	--#Region LA_GroupMinFeeHeader
	DELETE
	FROM dbo.LA_GroupMinFeeHeader
	WHERE GroupMinFeeID = @GroupMinFeeId
	--#Endregion LA_GroupMinFeeHeader
	
	--#Region LA_GroupMinFeeAssignment
	DELETE
	FROM dbo.LA_GroupMinFeeAssignment
	WHERE GroupMinFeeID = @GroupMinFeeId
	--#Endregion LA_GroupMinFeeAssignment
	
	--#Region LA_GroupMinFeeDetail
	DELETE
	FROM dbo.LA_GroupMinFeeDetail
	WHERE GroupMinFeeID = @GroupMinFeeId
	--#Endregion LA_GroupMinFeeDetail
END
GO
