/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20241211@Danny
	DB: DBCUST.bodb_licensee
	Description: 
*/

USE bodb_licensee
GO

insert into LA_DiscountGroupAssignment (DiscountGroupId,	PartyID,	Remark,	IsApplyDiscount,	IsSpecialTreatment)
select 791,1185,Null, 0, 0



