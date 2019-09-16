/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_UserSettingDel]
	@Id				INT,
	@ErrCode		INT				= 0		OUTPUT, 
	@ErrMsg			VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20190916@Parsons
	Task : Save query filters in LPID report [#FeatureId 119536]
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190916@Parsons: add new sp

	Param's Explannation: 
*/
BEGIN
	SET NOCOUNT ON
	IF EXISTS (SELECT TOP 1 1 FROM [dbo].[LA_UserSettings] WITH(NOLOCK) WHERE Id = @Id)
	BEGIN
		DELETE [dbo].[LA_UserSettings]
		WHERE Id = @Id 

		IF @@ERROR <> 0
		BEGIN
			SELECT 	@ErrMsg = 'Delete failed. Please try again.', @ErrCode = 501	
			RETURN
		END
	END
	ELSE
	BEGIN
		SELECT 	@ErrMsg = 'Filter does not exist. Please try again.', @ErrCode = 500	
		RETURN
	END
END
GO